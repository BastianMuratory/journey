// ===========================================================================
//  MODEL BROWSER — Processing 4 (Java mode) · P3D renderer
//
//  Browses a folder tree of OBJ models laid out like:
//     root/
//       0001_#0001 Bulbasaur/
//         001 - Bulbasaur.obj / .mtl / .png
//         001 - Bulbasaur - Shiny.obj / .mtl / .png
//       0002_#0002 Ivysaur/ ...
//
//  Any folder that contains .obj files becomes one entry in the list, and
//  every .obj inside it becomes a selectable variant (normal, shiny, forms).
//
//  Includes its own OBJ+MTL parser, so textures resolve correctly from
//  absolute paths (Processing's built-in loadShape() is unreliable there).
// ===========================================================================

import java.util.Collections;
import java.util.Comparator;

// ------------------------------------------------------------------ config
String ROOT_PATH = "";      // e.g. "/home/you/models" — leave "" to be asked at launch
int    SIDEBAR_W = 330;
int    BOTTOM_H  = 62;
int    ROW_H     = 26;
int    CACHE_MAX = 8;       // how many parsed models to keep in RAM

// ------------------------------------------------------------------ colours
final int C_BG       = #16181B;
final int C_PANEL    = #101214;
final int C_LINE     = #26292E;
final int C_TEXT     = #D8DBE0;
final int C_DIM      = #6E747D;
final int C_ACCENT   = #E0A65A;   // normal variants
final int C_SHINY    = #B48CE0;   // shiny variants

// ------------------------------------------------------------------- state
ArrayList<Item> items  = new ArrayList<Item>();
ArrayList<Item> shown  = new ArrayList<Item>();
int     sel      = -1;
int     varIdx   = 0;
String  query    = "";
boolean searchFocus = false;
float   scrollY  = 0;

float   yaw = 0, pitch = -0.12, zoomF = 1, panX = 0, panY = 0;
boolean spin = false, showGrid = true, wire = false, depthSort = false;
boolean preferShiny = false;
int     bgMode = 0;

HashMap<String, Model>  modelCache = new HashMap<String, Model>();
ArrayList<String>       cacheOrder = new ArrayList<String>();
HashMap<String, PImage> texCache   = new HashMap<String, PImage>();

String  pendingLoad = null;
String  pendingRoot = null;
boolean staleSelection = false;
boolean askedFolder = false;
String  status = "";
PFont   fSmall, fBig;
ArrayList<float[]> chips = new ArrayList<float[]>();

// ===========================================================================
//  SETUP / DRAW
// ===========================================================================

void setup() {
  size(1400, 900, P3D);
  surface.setTitle("Model Browser");
  surface.setResizable(true);
  textureWrap(REPEAT);
  fSmall = createFont("SansSerif", 13, true);
  fBig   = createFont("SansSerif", 17, true);
  if (ROOT_PATH.length() > 0) pendingRoot = ROOT_PATH;
}

void draw() {
  if (pendingRoot == null && !askedFolder && ROOT_PATH.length() == 0) {
    askedFolder = true;
    selectFolder("Select the folder that holds your model folders", "folderPicked");
  }
  if (pendingRoot != null) { String r = pendingRoot; pendingRoot = null; scan(r); }

  int vpX = SIDEBAR_W, vpW = width - SIDEBAR_W, vpH = height - BOTTOM_H;
  background(bgColor());
  perspective(PI / 3.0, float(width) / float(height), 1, 200000);

  Model m = currentModel();
  if (m != null && vpW > 0) {
    clip(vpX, 0, vpW, vpH);
    ambientLight(72, 74, 80);
    directionalLight(190, 188, 182, -0.45, 0.62, -0.65);
    directionalLight(70, 78, 95, 0.55, -0.35, 0.45);

    if (spin) yaw += 0.007;
    float s = fitScale(m, vpW, vpH) * zoomF;

    pushMatrix();
    translate(vpX + vpW * 0.5 + panX, vpH * 0.52 + panY, 0);
    rotateX(pitch);
    rotateY(yaw);
    scale(s);
    translate(-m.center.x, -m.center.y, -m.center.z);
    if (showGrid) drawGrid(m);
    shape(m.shape);
    popMatrix();

    noLights();
    noClip();
  }

  hint(DISABLE_DEPTH_TEST);
  camera();
  noLights();
  drawSidebar();
  drawBottomBar(m, vpX, vpW);
  if (pendingLoad != null) toast("Loading…", vpX + vpW * 0.5, height * 0.5);
  if (items.isEmpty()) toast(status.length() > 0 ? status : "Press O to choose your models folder",
                             vpX + vpW * 0.5, height * 0.5);
  hint(ENABLE_DEPTH_TEST);

  // deferred so the "Loading…" frame actually reaches the screen first
  if (pendingLoad != null) {
    String p = pendingLoad;
    pendingLoad = null;
    if (!modelCache.containsKey(p)) {
      Model nm = loadOBJ(p);
      if (nm != null) {
        modelCache.put(p, nm);
        cacheOrder.add(p);
        while (cacheOrder.size() > CACHE_MAX) modelCache.remove(cacheOrder.remove(0));
        applyWire(nm.shape, wire);
      }
    }
  }
}

void folderPicked(File f) {
  if (f != null) pendingRoot = f.getAbsolutePath();
  else status = "No folder selected. Press O to try again.";
}

int bgColor() {
  if (bgMode == 0) return C_BG;
  if (bgMode == 1) return #2B2F36;
  if (bgMode == 2) return #E8E8E6;
  return #000000;
}

// ===========================================================================
//  LIBRARY SCAN
// ===========================================================================

void scan(String root) {
  items.clear(); shown.clear(); modelCache.clear(); cacheOrder.clear(); texCache.clear();
  sel = -1; scrollY = 0;
  File rf = new File(root);
  if (!rf.isDirectory()) { status = "Not a folder: " + root; return; }
  ROOT_PATH = root;
  collect(rf, 0);
  Collections.sort(items, new Comparator<Item>() {
    public int compare(Item a, Item b) { return a.label.compareToIgnoreCase(b.label); }
  });
  applyFilter();
  status = items.size() + " models";
  surface.setTitle("Model Browser — " + rf.getName() + "  (" + items.size() + ")");
  if (!shown.isEmpty()) select(0);
}

void collect(File dir, int depth) {
  File[] fs = dir.listFiles();
  if (fs == null) return;
  ArrayList<File> objs = new ArrayList<File>();
  ArrayList<File> subs = new ArrayList<File>();
  for (File f : fs) {
    if (f.isDirectory()) subs.add(f);
    else if (f.getName().toLowerCase().endsWith(".obj")) objs.add(f);
  }
  if (!objs.isEmpty()) {
    Item it = new Item();
    it.dir   = dir.getAbsolutePath();
    it.label = prettify(dir.getName());
    for (File o : objs) {
      Variant v = new Variant();
      v.path  = o.getAbsolutePath();
      v.label = o.getName().substring(0, o.getName().length() - 4);
      v.shiny = v.label.toLowerCase().contains("shiny");
      it.vars.add(v);
    }
    // Plain filename order puts "Name - Shiny.obj" before "Name.obj" (space
    // sorts before dot), so order deliberately: base forms first.
    Collections.sort(it.vars, new Comparator<Variant>() {
      public int compare(Variant a, Variant b) {
        if (a.shiny != b.shiny) return a.shiny ? 1 : -1;
        return a.label.compareToIgnoreCase(b.label);
      }
    });
    it.key = (it.label + " " + dir.getName()).toLowerCase();
    items.add(it);
  }
  if (depth < 4) for (File s : subs) collect(s, depth + 1);
}

String prettify(String n) {
  String s = n;
  int u = s.indexOf('_');
  if (u > 0 && s.substring(0, u).matches("\\d+")) s = s.substring(u + 1);
  return s.replace("#", "").trim();
}

void applyFilter() {
  Item keep = (sel >= 0 && sel < shown.size()) ? shown.get(sel) : null;
  shown.clear();
  String[] words = splitTokens(query.toLowerCase());
  for (Item it : items) {
    boolean ok = true;
    for (String w : words) if (it.key.indexOf(w) < 0) { ok = false; break; }
    if (ok) shown.add(it);
  }
  sel = -1;
  if (keep != null) sel = shown.indexOf(keep);
  if (sel < 0 && !shown.isEmpty()) select(0); else ensureVisible();
}

void blurSearch() {
  searchFocus = false;
  if (staleSelection) requestLoad();
}

void select(int i) {
  if (i < 0 || i >= shown.size()) return;
  sel = i;
  Item it = shown.get(sel);
  varIdx = 0;
  for (int k = 0; k < it.vars.size(); k++)
    if (it.vars.get(k).shiny == preferShiny) { varIdx = k; break; }
  requestLoad();
  ensureVisible();
}

Variant currentVariant() {
  if (sel < 0 || sel >= shown.size()) return null;
  Item it = shown.get(sel);
  if (varIdx < 0 || varIdx >= it.vars.size()) return null;
  return it.vars.get(varIdx);
}

Model currentModel() {
  Variant v = currentVariant();
  return (v == null) ? null : modelCache.get(v.path);
}

void requestLoad() {
  // While filtering, the highlighted row changes on every keystroke — don't
  // parse a model for each one. The load happens when the field is left.
  if (searchFocus) { staleSelection = true; return; }
  staleSelection = false;
  Variant v = currentVariant();
  panX = panY = 0;
  if (v == null) return;
  if (modelCache.containsKey(v.path)) { applyWire(modelCache.get(v.path).shape, wire); return; }
  pendingLoad = v.path;
}

float fitScale(Model m, int vpW, int vpH) {
  return (min(vpW, vpH) * 0.40) / max(m.radius, 0.0001);
}

// ===========================================================================
//  OBJ / MTL LOADING
// ===========================================================================

class Vert { float x, y, z, u, v, nx, ny, nz; boolean hasN, hasUV; }
class Mat   { PImage tex = null; int col = #DCDCDC; float alpha = 255; }
class Batch { Mat mat; ArrayList<Vert> verts = new ArrayList<Vert>(); Batch(Mat m) { mat = m; } }

class Model {
  PShape shape;
  PVector center = new PVector();
  float radius = 1, groundY = 0;
  int tris = 0, parts = 0;
  boolean textured = false;
}

class Variant { String label, path; boolean shiny; }

class Item {
  String label, dir, key;
  ArrayList<Variant> vars = new ArrayList<Variant>();
}

Model loadOBJ(String path) {
  File objFile = new File(path);
  File dir = objFile.getParentFile();
  String[] lines;
  try { lines = loadStrings(objFile); } catch (Exception ex) { return null; }
  if (lines == null) return null;

  HashMap<String, Mat> mats = new HashMap<String, Mat>();
  Mat def = new Mat();
  Mat cur = def;

  ArrayList<PVector> vs = new ArrayList<PVector>();
  ArrayList<PVector> ts = new ArrayList<PVector>();
  ArrayList<PVector> ns = new ArrayList<PVector>();

  ArrayList<Batch> batches = new ArrayList<Batch>();
  HashMap<Mat, Batch> bmap = new HashMap<Mat, Batch>();
  Batch cb = null;

  float minX =  Float.MAX_VALUE, minY =  Float.MAX_VALUE, minZ =  Float.MAX_VALUE;
  float maxX = -Float.MAX_VALUE, maxY = -Float.MAX_VALUE, maxZ = -Float.MAX_VALUE;

  for (String raw : lines) {
    String line = raw.trim();
    if (line.length() == 0 || line.charAt(0) == '#') continue;
    int sp = firstSpace(line);
    String key  = (sp < 0) ? line : line.substring(0, sp);
    String rest = (sp < 0) ? ""   : line.substring(sp + 1).trim();

    if (key.equals("v")) {
      String[] t = splitTokens(rest);
      if (t.length < 3) continue;
      // OBJ is Y-up / right-handed; Processing screen space is Y-down.
      // Negating Y here makes the model appear exactly as it does in Blender.
      float x = float(t[0]), y = -float(t[1]), z = float(t[2]);
      if (Float.isNaN(x) || Float.isNaN(y) || Float.isNaN(z)) continue;
      vs.add(new PVector(x, y, z));
      minX = min(minX, x); maxX = max(maxX, x);
      minY = min(minY, y); maxY = max(maxY, y);
      minZ = min(minZ, z); maxZ = max(maxZ, z);

    } else if (key.equals("vt")) {
      String[] t = splitTokens(rest);
      if (t.length < 1) continue;
      float u = float(t[0]);
      float v = (t.length > 1) ? float(t[1]) : 0;
      ts.add(new PVector(u, 1 - v, 0));          // OBJ V origin is bottom-left

    } else if (key.equals("vn")) {
      String[] t = splitTokens(rest);
      if (t.length < 3) continue;
      ns.add(new PVector(float(t[0]), -float(t[1]), float(t[2])));

    } else if (key.equals("f")) {
      String[] t = splitTokens(rest);
      if (t.length < 3) continue;
      if (cb == null) {
        cb = bmap.get(cur);
        if (cb == null) { cb = new Batch(cur); bmap.put(cur, cb); batches.add(cb); }
      }
      for (int k = 2; k < t.length; k++) {      // fan-triangulate n-gons
        addVert(cb, t[0],     vs, ts, ns);
        addVert(cb, t[k - 1], vs, ts, ns);
        addVert(cb, t[k],     vs, ts, ns);
      }

    } else if (key.equals("usemtl")) {
      Mat m = mats.get(rest);
      cur = (m == null) ? def : m;
      cb = null;

    } else if (key.equals("mtllib")) {
      parseMTL(new File(dir, rest), mats, dir);
    }
  }

  if (vs.isEmpty() || batches.isEmpty()) return null;

  // Fallback: untextured but UV-mapped model sitting next to a lone PNG.
  boolean anyTex = false, anyUV = false;
  for (Batch b : batches) if (b.mat.tex != null) anyTex = true;
  if (!ts.isEmpty()) anyUV = true;
  if (!anyTex && anyUV) {
    PImage guess = guessTexture(objFile, dir);
    if (guess != null) for (Batch b : batches) b.mat.tex = guess;
  }

  PShape group = createShape(GROUP);
  int triCount = 0;
  for (Batch b : batches) {
    if (b.verts.size() < 3) continue;
    fillMissingNormals(b);
    boolean tex = (b.mat.tex != null);
    PShape s = createShape();
    s.beginShape(TRIANGLES);
    s.textureMode(NORMAL);
    s.noStroke();
    if (tex) { s.texture(b.mat.tex); s.fill(255, b.mat.alpha); }
    else     { s.fill(b.mat.col, b.mat.alpha); }
    for (Vert vv : b.verts) {
      if (vv.hasN) s.normal(vv.nx, vv.ny, vv.nz);
      if (tex) s.vertex(vv.x, vv.y, vv.z, vv.u, vv.v);
      else     s.vertex(vv.x, vv.y, vv.z);
    }
    s.endShape();
    group.addChild(s);
    triCount += b.verts.size() / 3;
  }

  Model m = new Model();
  m.shape  = group;
  m.center = new PVector((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5);
  m.radius = max(0.0001, 0.5 * dist(minX, minY, minZ, maxX, maxY, maxZ));
  m.groundY = maxY;                     // Y is flipped, so "down" is the max
  m.tris = triCount;
  m.parts = group.getChildCount();
  m.textured = anyTex;
  return m;
}

void addVert(Batch b, String tok, ArrayList<PVector> vs, ArrayList<PVector> ts, ArrayList<PVector> ns) {
  String[] p = split(tok, '/');
  int vi = parseIdx(p[0], vs.size());
  if (vi < 0 || vi >= vs.size()) return;
  PVector v = vs.get(vi);
  Vert out = new Vert();
  out.x = v.x; out.y = v.y; out.z = v.z;
  if (p.length > 1 && p[1].length() > 0) {
    int ti = parseIdx(p[1], ts.size());
    if (ti >= 0 && ti < ts.size()) { PVector t = ts.get(ti); out.u = t.x; out.v = t.y; out.hasUV = true; }
  }
  if (p.length > 2 && p[2].length() > 0) {
    int ni = parseIdx(p[2], ns.size());
    if (ni >= 0 && ni < ns.size()) { PVector n = ns.get(ni); out.nx = n.x; out.ny = n.y; out.nz = n.z; out.hasN = true; }
  }
  b.verts.add(out);
}

int parseIdx(String s, int n) {
  try {
    int i = Integer.parseInt(s.trim());
    return (i > 0) ? i - 1 : n + i;      // negative indices are relative
  } catch (Exception ex) { return -1; }
}

void fillMissingNormals(Batch b) {
  for (int i = 0; i + 2 < b.verts.size(); i += 3) {
    Vert a = b.verts.get(i), c = b.verts.get(i + 1), d = b.verts.get(i + 2);
    if (a.hasN && c.hasN && d.hasN) continue;
    float ux = c.x - a.x, uy = c.y - a.y, uz = c.z - a.z;
    float vx = d.x - a.x, vy = d.y - a.y, vz = d.z - a.z;
    float nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    float len = sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-9) continue;
    nx /= len; ny /= len; nz /= len;
    for (Vert q : new Vert[] { a, c, d }) {
      if (!q.hasN) { q.nx = nx; q.ny = ny; q.nz = nz; q.hasN = true; }
    }
  }
}

void parseMTL(File f, HashMap<String, Mat> mats, File dir) {
  if (f == null || !f.exists()) return;
  String[] lines;
  try { lines = loadStrings(f); } catch (Exception ex) { return; }
  if (lines == null) return;
  Mat cur = null;
  for (String raw : lines) {
    String line = raw.trim();
    if (line.length() == 0 || line.charAt(0) == '#') continue;
    int sp = firstSpace(line);
    String key  = (sp < 0) ? line : line.substring(0, sp);
    String rest = (sp < 0) ? ""   : line.substring(sp + 1).trim();

    if (key.equals("newmtl")) { cur = new Mat(); mats.put(rest, cur); }
    else if (cur == null) continue;
    else if (key.equals("Kd")) {
      String[] t = splitTokens(rest);
      if (t.length >= 3) cur.col = color(float(t[0]) * 255, float(t[1]) * 255, float(t[2]) * 255);
    }
    else if (key.equals("d"))  cur.alpha = constrain(float(rest) * 255, 0, 255);
    else if (key.equals("Tr")) cur.alpha = constrain((1 - float(rest)) * 255, 0, 255);
    else if (key.equals("map_Kd") || key.equals("map_Ka")) {
      if (cur.tex == null) cur.tex = findTexture(rest, dir);
    }
  }
}

// Resolves a map_Kd value against the model folder. Handles filenames with
// spaces, option flags, Windows paths, wrong case and swapped extensions.
PImage findTexture(String spec, File dir) {
  String s = spec.trim();
  while (s.startsWith("-")) {                       // strip "-s 1 1 1" style options
    String[] t = splitTokens(s);
    int i = 1;
    while (i < t.length && (isNumeric(t[i]) || t[i].equals("on") || t[i].equals("off"))) i++;
    if (i >= t.length) return null;
    s = join(subset(t, i), " ");
  }
  s = s.replace('\\', '/');
  if (s.indexOf('/') >= 0) s = s.substring(s.lastIndexOf('/') + 1);
  if (s.length() == 0) return null;

  File f = new File(dir, s);
  if (!f.exists()) f = fuzzyFile(dir, s);
  if (f == null) return null;
  return cachedImage(f);
}

File fuzzyFile(File dir, String name) {
  File[] fs = dir.listFiles();
  if (fs == null) return null;
  String want = name.toLowerCase();
  String stem = want.contains(".") ? want.substring(0, want.lastIndexOf('.')) : want;
  for (File f : fs) if (f.getName().toLowerCase().equals(want)) return f;
  for (File f : fs) {                                // same name, different extension
    String n = f.getName().toLowerCase();
    if (!isImage(n)) continue;
    String st = n.contains(".") ? n.substring(0, n.lastIndexOf('.')) : n;
    if (st.equals(stem)) return f;
  }
  return null;
}

PImage guessTexture(File objFile, File dir) {
  String stem = objFile.getName().substring(0, objFile.getName().length() - 4).toLowerCase();
  File[] fs = dir.listFiles();
  if (fs == null) return null;
  File best = null;
  int imgs = 0;
  for (File f : fs) {
    String n = f.getName().toLowerCase();
    if (!isImage(n)) continue;
    imgs++;
    String st = n.substring(0, n.lastIndexOf('.'));
    if (st.equals(stem)) best = f;
    if (best == null && imgs == 1) best = f;
  }
  return (best == null) ? null : cachedImage(best);
}

boolean isImage(String n) {
  return n.endsWith(".png") || n.endsWith(".jpg") || n.endsWith(".jpeg") || n.endsWith(".bmp");
}

boolean isNumeric(String s) {
  try { Float.parseFloat(s); return true; } catch (Exception ex) { return false; }
}

PImage cachedImage(File f) {
  String k = f.getAbsolutePath();
  if (texCache.containsKey(k)) return texCache.get(k);
  PImage img = null;
  try { img = loadImage(k); } catch (Exception ex) { img = null; }
  texCache.put(k, img);
  return img;
}

int firstSpace(String s) {
  for (int i = 0; i < s.length(); i++) {
    char c = s.charAt(i);
    if (c == ' ' || c == '\t') return i;
  }
  return -1;
}

void applyWire(PShape s, boolean on) {
  if (s == null) return;
  s.setStroke(on);
  if (on) { s.setStroke(color(255, 70)); s.setStrokeWeight(1); }
  for (int i = 0; i < s.getChildCount(); i++) applyWire(s.getChild(i), on);
}

// ===========================================================================
//  3D DECOR
// ===========================================================================

void drawGrid(Model m) {
  float r = m.radius;
  float y = m.groundY + r * 0.002;
  float ext = r * 1.5, step = r * 0.25;
  float cx = m.center.x, cz = m.center.z;
  strokeWeight(1);
  noFill();
  for (float o = -ext; o <= ext + 0.001; o += step) {
    boolean axis = abs(o) < step * 0.5;
    stroke(255, axis ? 46 : 20);
    line(cx - ext, y, cz + o, cx + ext, y, cz + o);
    line(cx + o, y, cz - ext, cx + o, y, cz + ext);
  }
  noStroke();
}

// ===========================================================================
//  INTERFACE
// ===========================================================================

void drawSidebar() {
  noStroke();
  fill(C_PANEL);
  rect(0, 0, SIDEBAR_W, height);
  stroke(C_LINE); line(SIDEBAR_W, 0, SIDEBAR_W, height); noStroke();

  // search field
  int sy = 14, sh = 32;
  fill(searchFocus ? #1B1E23 : #15181B);
  stroke(searchFocus ? accent() : C_LINE);
  rect(14, sy, SIDEBAR_W - 28, sh, 4);
  noStroke();
  textFont(fSmall);
  textAlign(LEFT, CENTER);
  if (query.length() == 0) {
    fill(C_DIM);
    text(searchFocus ? "type to filter…" : "press  /  to search", 26, sy + sh / 2 - 1);
  } else {
    fill(C_TEXT);
    text(query, 26, sy + sh / 2 - 1);
    if (searchFocus && (frameCount / 24) % 2 == 0) {
      float cx = 26 + textWidth(query) + 2;
      stroke(accent()); line(cx, sy + 8, cx, sy + sh - 8); noStroke();
    }
  }

  // list
  int top = sy + sh + 12;
  int bot = height - 30;
  float maxScroll = max(0, shown.size() * ROW_H - (bot - top));
  scrollY = constrain(scrollY, 0, maxScroll);

  int first = max(0, floor(scrollY / ROW_H));
  int last  = min(shown.size(), first + ceil((bot - top) / (float) ROW_H) + 1);
  textFont(fSmall);
  for (int i = first; i < last; i++) {
    float y = top + i * ROW_H - scrollY;
    if (y + ROW_H < top || y > bot) continue;
    boolean isSel = (i == sel);
    boolean hover = mouseX < SIDEBAR_W && mouseY > y && mouseY < y + ROW_H && mouseY > top && mouseY < bot;
    if (isSel) { fill(accent(), 34); rect(8, y, SIDEBAR_W - 16, ROW_H - 2, 3); }
    else if (hover) { fill(255, 10); rect(8, y, SIDEBAR_W - 16, ROW_H - 2, 3); }
    if (isSel) { fill(accent()); rect(8, y, 3, ROW_H - 2, 2); }
    fill(isSel ? C_TEXT : #A9AEB6);
    textAlign(LEFT, CENTER);
    text(ellipsize(shown.get(i).label, SIDEBAR_W - 62), 22, y + ROW_H / 2 - 1);
    int nv = shown.get(i).vars.size();
    if (nv > 1) {
      fill(C_DIM);
      textAlign(RIGHT, CENTER);
      text(nv, SIDEBAR_W - 22, y + ROW_H / 2 - 1);
    }
  }

  // scrollbar
  if (maxScroll > 0) {
    float trackH = bot - top;
    float h = max(24, trackH * trackH / (shown.size() * ROW_H));
    float y = top + (trackH - h) * (scrollY / maxScroll);
    fill(255, 26);
    rect(SIDEBAR_W - 7, y, 3, h, 2);
  }

  fill(C_DIM);
  textAlign(LEFT, CENTER);
  text(shown.size() + (shown.size() == items.size() ? " models" : " of " + items.size()), 16, height - 16);
  textAlign(RIGHT, CENTER);
  text("O  change folder", SIDEBAR_W - 16, height - 16);
}

void drawBottomBar(Model m, int vpX, int vpW) {
  chips.clear();
  float y0 = height - BOTTOM_H;
  noStroke();
  fill(C_PANEL);
  rect(vpX + 1, y0, vpW, BOTTOM_H);
  stroke(C_LINE); line(vpX, y0, width, y0); noStroke();

  Item it = (sel >= 0 && sel < shown.size()) ? shown.get(sel) : null;
  Variant v = currentVariant();

  textAlign(LEFT, CENTER);
  if (it != null) {
    textFont(fBig);
    fill(C_TEXT);
    text(ellipsize(it.label, vpW * 0.45), vpX + 20, y0 + 21);
    textFont(fSmall);
    fill(C_DIM);
    String info = (m == null) ? "…" : nf(m.tris, 0) + " tris · " + m.parts + (m.parts == 1 ? " part" : " parts")
                                      + (m.textured ? " · textured" : " · vertex colour");
    text(info, vpX + 20, y0 + 43);

    // variant chips
    float cx = vpX + 20 + max(textWidth(ellipsize(it.label, vpW * 0.45)) + 24, 220);
    textFont(fSmall);
    for (int i = 0; i < it.vars.size(); i++) {
      Variant vv = it.vars.get(i);
      String lb = shortVariant(vv, it);
      float w = textWidth(lb) + 22;
      if (cx + w > width - 20) break;
      boolean on = (i == varIdx);
      int ac = vv.shiny ? C_SHINY : C_ACCENT;
      fill(on ? ac : #1A1D21);
      stroke(on ? ac : C_LINE);
      rect(cx, y0 + 17, w, 26, 13);
      noStroke();
      fill(on ? #101214 : #9AA0A8);
      textAlign(CENTER, CENTER);
      text(lb, cx + w / 2, y0 + 29);
      chips.add(new float[] { cx, y0 + 17, w, 26, i });
      cx += w + 8;
    }
  }

  textFont(fSmall);
  fill(#4B5057);
  textAlign(RIGHT, CENTER);
  text("drag orbit · shift-drag pan · wheel zoom · ←/→ variant · S shiny · R spin · G grid · W wire · F fit · B bg · T sort · P png",
       width - 20, y0 + BOTTOM_H - 14);
}

// "001 - Bulbasaur"         -> "Normal"
// "001 - Bulbasaur - Shiny" -> "Shiny"
String shortVariant(Variant v, Item it) {
  String s = v.label;
  int d = s.indexOf(" - ");
  if (d > 0 && s.substring(0, d).trim().matches("[0-9#]+")) s = s.substring(d + 3);
  int d2 = s.indexOf(" - ");
  if (d2 >= 0) return s.substring(d2 + 3);
  return "Normal";
}

String ellipsize(String s, float w) {
  if (textWidth(s) <= w) return s;
  String out = s;
  while (out.length() > 1 && textWidth(out + "…") > w) out = out.substring(0, out.length() - 1);
  return out + "…";
}

void toast(String msg, float cx, float cy) {
  textFont(fSmall);
  textAlign(CENTER, CENTER);
  float w = textWidth(msg) + 36;
  noStroke();
  fill(0, 150);
  rect(cx - w / 2, cy - 18, w, 36, 18);
  fill(C_TEXT);
  text(msg, cx, cy - 1);
}

int accent() {
  Variant v = currentVariant();
  return (v != null && v.shiny) ? C_SHINY : C_ACCENT;
}

void ensureVisible() {
  if (sel < 0) return;
  int top = 14 + 32 + 12, bot = height - 30;
  float y = sel * ROW_H;
  if (y < scrollY) scrollY = y;
  if (y + ROW_H > scrollY + (bot - top)) scrollY = y + ROW_H - (bot - top);
}

// ===========================================================================
//  INPUT
// ===========================================================================

void mousePressed() {
  if (mouseX < SIDEBAR_W) {
    int sy = 14, sh = 32;
    if (mouseY > sy && mouseY < sy + sh) { searchFocus = true; return; }
    blurSearch();
    int top = sy + sh + 12, bot = height - 30;
    if (mouseY > top && mouseY < bot) {
      int i = floor((mouseY - top + scrollY) / ROW_H);
      if (i >= 0 && i < shown.size()) select(i);
    }
    return;
  }
  blurSearch();
  for (float[] c : chips) {
    if (mouseX > c[0] && mouseX < c[0] + c[2] && mouseY > c[1] && mouseY < c[1] + c[3]) {
      varIdx = int(c[4]);
      Variant v = currentVariant();
      if (v != null) preferShiny = v.shiny;
      requestLoad();
      return;
    }
  }
}

void mouseDragged() {
  if (mouseX < SIDEBAR_W) return;
  float dx = mouseX - pmouseX, dy = mouseY - pmouseY;
  if (mouseButton == RIGHT || mouseButton == CENTER || (keyPressed && keyCode == SHIFT)) {
    panX += dx; panY += dy;
  } else {
    yaw   += dx * 0.01;
    pitch += dy * 0.01;
    pitch = constrain(pitch, -HALF_PI * 0.99, HALF_PI * 0.99);
  }
}

void mouseWheel(MouseEvent e) {
  float d = e.getCount();
  if (mouseX < SIDEBAR_W) scrollY = constrain(scrollY + d * ROW_H * 2, 0, max(0, shown.size() * ROW_H - (height - 30 - 58)));
  else zoomF = constrain(zoomF * exp(-d * 0.14), 0.03, 60);
}

void keyPressed() {
  if (key == ESC) { key = 0; blurSearch(); return; }

  if (searchFocus) {
    if (key == BACKSPACE) {
      if (query.length() > 0) { query = query.substring(0, query.length() - 1); applyFilter(); }
      return;
    }
    if (key == ENTER || key == RETURN) { blurSearch(); return; }
    if (key == CODED) { arrows(); return; }
    if (key >= 32 && key < 127) { query += key; applyFilter(); return; }
    return;
  }

  if (key == CODED) { arrows(); return; }

  switch (Character.toLowerCase(key)) {
    case '/': searchFocus = true; break;
    case 's':
      preferShiny = !preferShiny;
      if (sel >= 0) {
        Item it = shown.get(sel);
        for (int k = 0; k < it.vars.size(); k++)
          if (it.vars.get(k).shiny == preferShiny) { varIdx = k; requestLoad(); break; }
      }
      break;
    case 'r': spin = !spin; break;
    case 'g': showGrid = !showGrid; break;
    case 'b': bgMode = (bgMode + 1) % 4; break;
    case 'f': yaw = 0; pitch = -0.12; zoomF = 1; panX = panY = 0; break;
    case 'w':
      wire = !wire;
      Model m = currentModel();
      if (m != null) applyWire(m.shape, wire);
      break;
    case 't':
      depthSort = !depthSort;
      if (depthSort) hint(ENABLE_DEPTH_SORT); else hint(DISABLE_DEPTH_SORT);
      break;
    case 'p':
      Variant v = currentVariant();
      saveFrame("shots/" + ((v == null) ? "view" : v.label.replaceAll("[^A-Za-z0-9 _-]", "")) + "-####.png");
      break;
    case 'o': selectFolder("Select the folder that holds your model folders", "folderPicked"); break;
    case 'c': query = ""; applyFilter(); break;
  }
}

void arrows() {
  if (keyCode == UP)    select(sel - 1);
  if (keyCode == DOWN)  select(sel + 1);
  if (keyCode == LEFT || keyCode == RIGHT) {
    if (sel < 0) return;
    int n = shown.get(sel).vars.size();
    if (n < 2) return;
    varIdx = (varIdx + (keyCode == RIGHT ? 1 : n - 1)) % n;
    Variant v = currentVariant();
    if (v != null) preferShiny = v.shiny;
    requestLoad();
  }
  if (keyCode == java.awt.event.KeyEvent.VK_PAGE_UP)   select(max(0, sel - 12));
  if (keyCode == java.awt.event.KeyEvent.VK_PAGE_DOWN) select(min(shown.size() - 1, sel + 12));
}
