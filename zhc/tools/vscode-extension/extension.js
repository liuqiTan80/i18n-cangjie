// zhc 中文仓颉 VS Code 扩展（设计 §9）：行帧 LSP 客户端 + 诊断 + 右键运行 + 全角转换。
// 行帧协议（§13.1 实测）：与 zhc lsp 之间每帧为「一行 JSON + \n」——
// 仓颉 runtime 的 stdin/stdout 读为行语义，标准 LSP 帧头（Content-Length）
// 在 zhc 侧已由代理消化，扩展端只收发 JSON 行。
"use strict";

const vscode = require("vscode");
const child_process = require("child_process");
const readline = require("readline");
const fs = require("fs");
const path = require("path");

/** 全角 → 半角映射（§9.2 核心标点；字符串/注释内保留原文）。 */
const FULL_TO_HALF = {
  "（": "(", "）": ")", "，": ",", "；": ";", "：": ":",
  "！": "!", "？": "?", "＝": "=", "＋": "+", "－": "-",
  "＊": "*", "／": "/", "％": "%", "＜": "<", "＞": ">",
  "［": "[", "］": "]", "｛": "{", "｝": "}", "＃": "#",
  "＄": "$", "＠": "@", "＆": "&", "＾": "^", "＿": "_", "～": "~",
};

/**
 * 全角标点转换（词法状态机：区分字符串/字符/行注释/块注释，§9.2）。
 * 字符串内保留原文；配对引号场景（“ ”）不转换。
 */
function convertFullWidthText(text) {
  let out = "";
  let i = 0;
  let state = "code"; // code | str | chr | line | block
  while (i < text.length) {
    const c = text[i];
    const n = text[i + 1];
    if (state === "code") {
      if (c === '"') { state = "str"; out += c; i++; continue; }
      if (c === "'") { state = "chr"; out += c; i++; continue; }
      if (c === "/" && n === "/") { state = "line"; out += "//"; i += 2; continue; }
      if (c === "/" && n === "*") { state = "block"; out += "/*"; i += 2; continue; }
      out += FULL_TO_HALF[c] || c;
      i++;
    } else if (state === "str") {
      if (c === "\\") { out += c + (text[i + 1] || ""); i += 2; continue; }
      if (c === '"') { state = "code"; }
      out += c; i++;
    } else if (state === "chr") {
      if (c === "\\") { out += c + (text[i + 1] || ""); i += 2; continue; }
      if (c === "'") { state = "code"; }
      out += c; i++;
    } else if (state === "line") {
      if (c === "\n") { state = "code"; }
      out += c; i++;
    } else { // block
      if (c === "*" && n === "/") { state = "code"; out += "*/"; i += 2; continue; }
      out += c; i++;
    }
  }
  return out;
}

/** 可执行文件解析（§9.5）：配置路径 → 绝对路径 → PATH 扫描（win 补 PATHEXT）。 */
function resolveZhc() {
  const cfg = vscode.workspace.getConfiguration("zhc").get("binary", "zhc");
  if (path.isAbsolute(cfg) && fs.existsSync(cfg)) return cfg;
  const exts = (process.env.PATHEXT || ".EXE;.CMD;.BAT;.COM").split(";");
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    for (const ext of exts) {
      const cand = path.join(dir, cfg + ext.toLowerCase());
      if (fs.existsSync(cand)) return cand;
    }
    const plain = path.join(dir, cfg);
    if (fs.existsSync(plain) && fs.statSync(plain).isFile()) return plain;
  }
  return cfg; // 兜底：交给 spawn 报错并提示
}

/** 行帧 LSP 客户端（编辑器侧：发一行 JSON，收一行 JSON）。 */
class ZhcLspClient {
  constructor() {
    this.proc = null;
    this.ready = false;
    this.seq = 0;
    this.pending = new Map(); // id -> resolve
    this.diags = vscode.languages.createDiagnosticCollection("zhc");
  }

  start() {
    const bin = resolveZhc();
    const env = Object.assign({}, process.env);
    const langPacks = vscode.workspace.getConfiguration("zhc").get("langPacks", "");
    if (langPacks) env.ZHC_LANG_PACKS = langPacks;
    const lspBin = vscode.workspace.getConfiguration("zhc").get("lspServerPath", "");
    if (lspBin) env.ZHC_LSP_BIN = lspBin;
    this.proc = child_process.spawn(bin, ["lsp"], { env, stdio: ["pipe", "pipe", "pipe"] });
    this.proc.on("error", e => console.error("[zhc] 启动失败（请配置 zhc.binary）：", e.message));
    this.proc.stderr.on("data", d => console.log("[zhc]", d.toString().trim()));
    this.proc.on("exit", () => { this.ready = false; this.diags.clear(); });
    readline.createInterface({ input: this.proc.stdout }).on("line", line => {
      let msg;
      try { msg = JSON.parse(line); } catch (e) { return; }
      this.onMessage(msg);
    });
    const rootUri = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0]
      ? vscode.Uri.file(vscode.workspace.workspaceFolders[0].uri.fsPath).toString() : null;
    this.request("initialize", {
      processId: process.pid, rootUri, capabilities: {},
    }).then(() => {
      this.ready = true;
      this.send("initialized", {});
      for (const doc of vscode.workspace.textDocuments) this.syncOpen(doc);
    }).catch(e => console.error("[zhc] initialize 失败：", e.message));
  }

  stop() {
    if (this.proc) { try { this.proc.kill(); } catch (e) {} }
    this.diags.dispose();
  }

  send(method, params) {
    if (!this.proc || !this.proc.stdin.writable) return;
    const frame = { jsonrpc: "2.0", method, params };
    this.proc.stdin.write(JSON.stringify(frame) + "\n"); // 行帧
  }

  request(method, params) {
    return new Promise((resolve, reject) => {
      if (!this.proc || !this.proc.stdin.writable) return reject(new Error("server not running"));
      const id = ++this.seq;
      this.pending.set(id, resolve);
      this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
      setTimeout(() => { if (this.pending.delete(id)) resolve(null); }, 30000);
    });
  }

  onMessage(msg) {
    if (msg.id && this.pending.has(msg.id)) {
      this.pending.get(msg.id)(msg.result !== undefined ? msg.result : msg.error);
      this.pending.delete(msg.id);
    } else if (msg.method === "textDocument/publishDiagnostics") {
      this.applyDiags(msg.params);
    }
  }

  applyDiags(params) {
    const uri = vscode.Uri.parse(params.uri);
    const items = (params.diagnostics || []).map(d => {
      const r = d.range;
      const range = new vscode.Range(r.start.line, r.start.character, r.end.line, r.end.character);
      const diag = new vscode.Diagnostic(range, d.message,
        d.severity === 2 ? vscode.DiagnosticSeverity.Warning : vscode.DiagnosticSeverity.Error);
      diag.source = d.source || "zhc";
      return diag;
    });
    this.diags.set(uri, items);
  }

  syncOpen(doc) {
    if (doc.languageId !== "cangjie-zh" || !this.ready) return;
    this.send("textDocument/didOpen", {
      textDocument: {
        uri: doc.uri.toString(), languageId: doc.languageId,
        version: doc.version, text: doc.getText(),
      },
    });
  }
}

let client = null;

function activate(context) {
  client = new ZhcLspClient();
  client.start();

  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument(d => client.syncOpen(d)),
    vscode.workspace.onDidChangeTextDocument(e => {
      const d = e.document;
      if (d.languageId === "cangjie-zh" && client.ready) {
        // 强制全量同步（initialize 响应已由 zhc 改写 textDocumentSync=1）
        client.send("textDocument/didChange", {
          textDocument: { uri: d.uri.toString(), version: d.version },
          contentChanges: [{ text: d.getText() }],
        });
      }
    }),
    vscode.workspace.onDidCloseTextDocument(d => {
      if (d.languageId === "cangjie-zh" && client.ready) {
        client.send("textDocument/didClose", { textDocument: { uri: d.uri.toString() } });
      }
    }),
    vscode.commands.registerCommand("zhc.run", () => runInTerminal("run")),
    vscode.commands.registerCommand("zhc.check", () => runInTerminal("check")),
    vscode.commands.registerCommand("zhc.convertFullWidth", convertFullWidthCmd),
    vscode.commands.registerCommand("zhc.restartLsp", () => { client.stop(); client = new ZhcLspClient(); client.start(); })
  );
}

/** 终端运行/检查（§9.3）：PowerShell 带引号路径需 & 前缀（坑 ④）。 */
function runInTerminal(kind) {
  const ed = vscode.window.activeTextEditor;
  if (!ed || ed.document.languageId !== "cangjie-zh") {
    vscode.window.showWarningMessage("请先打开 .zc 方言文件");
    return;
  }
  const zhc = resolveZhc();
  const file = ed.document.uri.fsPath;
  const shell = process.platform === "win32" ? `& "${zhc}" ${kind} "${file}"` : `"${zhc}" ${kind} "${file}"`;
  const term = vscode.window.activeTerminal || vscode.window.createTerminal("zhc");
  term.show();
  term.sendText(shell);
}

/** 全角转换命令：选区优先，否则整个文档。 */
function convertFullWidthCmd() {
  const ed = vscode.window.activeTextEditor;
  if (!ed) return;
  const doc = ed.document;
  let range, text;
  if (!ed.selection.isEmpty) {
    range = new vscode.Range(ed.selection.start, ed.selection.end);
    text = doc.getText(range);
  } else {
    range = new vscode.Range(0, 0, doc.lineCount, 0);
    text = doc.getText();
  }
  const converted = convertFullWidthText(text);
  if (converted === text) {
    vscode.window.setStatusBarMessage("zhc：没有可转换的全角标点", 2000);
    return;
  }
  ed.edit(b => b.replace(range, converted));
  vscode.window.setStatusBarMessage(`zhc：已转换 ${countDiff(text, converted)} 处全角标点`, 3000);
}

function countDiff(a, b) {
  let n = 0;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) n++;
  return n;
}

function deactivate() {
  if (client) client.stop();
}

module.exports = { activate, deactivate, convertFullWidthText };
