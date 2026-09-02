// zhc 方言 VS Code 扩展（设计 §9.2 职责 1-5 + 阶段 4 行帧协议）
//
// 能力：
//   1. .zc 语言注册 + TextMate 语法高亮（tools/gen_highlight.py 从语言包生成）
//   2. 全角标点自动转换（输入时，字符串字面量内保留，词法状态机）
//   3. 右键运行 / 检查（终端 zhc run / check；PowerShell 需 `& ` 调用操作符，§9.2 职责 3）
//   4. 依赖添加命令（zhc add）
//   5. LSP 客户端：行帧协议（JSON 单行 + \n）驱动 zhc lsp 代理，
//      诊断经 publishDiagnostics 推送收集 → 编辑器标记；zhc 不可用自动降级提示
//   （官方 LSP 不可用时 zhc 代理自身降级为仅诊断档，扩展无需感知）
//
// zhc 可执行文件解析（跨平台）：配置 zhc.binPath → 环境变量 ZHC_BIN → PATH 扫描
// （Windows 按 PATHEXT 后缀探测）→ 用户主目录 ~/.zhc 回退。

const vscode = require('vscode');
const { spawn, execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { convertFullwidthText } = require('./lib/fullwidth');   // 建议 E4：纯函数抽离（node 单测）

// ---------- zhc 可执行文件解析（跨平台） ----------

function resolveZhcBin() {
  const cfg = vscode.workspace.getConfiguration('zhc');
  const fromCfg = cfg.get('binPath');
  if (fromCfg && fs.existsSync(fromCfg)) return fromCfg;
  const fromEnv = process.env.ZHC_BIN;
  if (fromEnv && fs.existsSync(fromEnv)) return fromEnv;
  const exts = (process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';');
  const candidates = ['zhc', 'zhc.exe', 'zhc.cmd', 'zhc.bat'];
  const dirs = (process.env.PATH || '').split(path.delimiter);
  for (const d of dirs) {
    if (!d) continue;
    for (const c of candidates) {
      const p = path.join(d, c);
      if (fs.existsSync(p)) return p;
      for (const e of exts) {
        const pe = p + e.toLowerCase();
        if (fs.existsSync(pe)) return pe;
      }
    }
  }
  // 用户主目录回退：~/.zhc/bin/zhc 与 ~/.zhc/zhc
  const home = os.homedir();
  for (const p of [path.join(home, '.zhc', 'bin', 'zhc'), path.join(home, '.zhc', 'zhc')]) {
    if (fs.existsSync(p)) return p;
  }
  return 'zhc';
}

// ---------- 全角转换（词法状态机在 lib/fullwidth.js，node 单测覆盖） ----------

// ---------- LSP 客户端（行帧协议驱动 zhc lsp 代理） ----------

class ZhcLspClient {
  constructor() {
    this.proc = null;
    this.buf = '';
    this.pending = new Map();   // id -> resolve
    this.nextId = 1;
    this.diags = vscode.languages.createDiagnosticCollection('zhc');
    this.ready = false;
  }

  start() {
    const bin = resolveZhcBin();
    const env = Object.assign({}, process.env, { ZHC_LANG_PACKS: process.env.ZHC_LANG_PACKS || '' });
    this.proc = spawn(bin, ['lsp'], { env });
    this.proc.stdout.on('data', (d) => this.onData(d.toString('utf8')));
    this.proc.stderr.on('data', (d) => {
      const t = d.toString('utf8').trim();
      if (t) console.log('[zhc-lsp]', t);
    });
    this.proc.on('exit', (code) => {
      this.ready = false;
      console.log('[zhc-lsp] 退出，code=' + code);
    });
    this.proc.on('error', (err) => {
      console.log('[zhc-lsp] 启动失败：' + err.message);
    });
  }

  onData(chunk) {
    this.buf += chunk;
    let nl;
    while ((nl = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, nl).trim();
      this.buf = this.buf.slice(nl + 1);
      if (!line) continue;
      try {
        this.onMessage(JSON.parse(line));
      } catch (e) {
        console.log('[zhc-lsp] 非 JSON 帧：' + line.slice(0, 80));
      }
    }
  }

  onMessage(msg) {
    if (msg.id !== undefined && this.pending.has(msg.id)) {
      this.pending.get(msg.id)(msg);
      this.pending.delete(msg.id);
      return;
    }
    if (msg.method === 'textDocument/publishDiagnostics') {
      this.applyDiagnostics(msg.params);
    }
  }

  applyDiagnostics(params) {
    const uri = vscode.Uri.parse(params.uri);
    const items = (params.diagnostics || []).map((d) => {
      const r = d.range || { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } };
      const range = new vscode.Range(r.start.line, r.start.character, r.end.line, r.end.character);
      return new vscode.Diagnostic(range, d.message || '', d.severity === 2 ? vscode.DiagnosticSeverity.Warning : vscode.DiagnosticSeverity.Error);
    });
    this.diags.set(uri, items);
  }

  send(method, params, id) {
    const msg = { jsonrpc: '2.0', method, params };
    if (id !== undefined) {
      msg.id = id;
      this.pending.set(id, () => {});
    }
    if (this.proc && this.proc.stdin.writable) {
      this.proc.stdin.write(JSON.stringify(msg) + '\n');
    }
  }

  initialize(workspaceFolder) {
    const rootUri = workspaceFolder ? vscode.Uri.file(workspaceFolder.uri.fsPath).toString() : null;
    this.send('initialize', {
      processId: process.pid,
      rootUri,
      capabilities: {
        textDocument: {
          synchronization: { didOpen: true, didChange: true, didClose: true },
          hover: {}, definition: {}, completion: {}, semanticTokens: {},
        },
      },
    }, this.nextId++);
  }

  didOpen(doc) {
    this.send('textDocument/didOpen', {
      textDocument: {
        uri: doc.uri.toString(),
        languageId: doc.languageId,
        version: doc.version,
        text: doc.getText(),
      },
    });
  }

  didChange(doc) {
    this.send('textDocument/didChange', {
      textDocument: { uri: doc.uri.toString(), version: doc.version },
      contentChanges: [{ text: doc.getText() }],
    });
  }

  didClose(doc) {
    this.send('textDocument/didClose', {
      textDocument: { uri: doc.uri.toString() },
    });
  }

  dispose() {
    this.diags.dispose();
    if (this.proc) {
      try { this.proc.kill(); } catch (e) { /* ignore */ }
    }
  }
}

// ---------- 命令实现 ----------

/** 终端运行 zhc（PowerShell 需 `& ` 调用操作符前缀，§9.2 职责 3）。 */
function runInTerminal(args, cwd) {
  const bin = resolveZhcBin();
  const isPwsh = process.platform === 'win32';
  let cmd;
  if (isPwsh) {
    // 带引号的可执行路径需 & 调用操作符；参数按平台引用转义防注入
    const quoted = '"' + bin.replace(/"/g, '""') + '"';
    const argStr = args.map((a) => '"' + a.replace(/"/g, '""') + '"').join(' ');
    cmd = '& ' + quoted + ' ' + argStr;
  } else {
    cmd = [bin].concat(args).map((a) => (/\s/.test(a) ? "'" + a + "'" : a)).join(' ');
  }
  const term = vscode.window.createTerminal({ name: 'zhc', cwd });
  term.show();
  term.sendText(cmd, true);
  return term;
}

function currentDir() {
  const doc = vscode.window.activeTextEditor && vscode.window.activeTextEditor.document;
  if (doc) return path.dirname(doc.fileName);
  return vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0].uri.fsPath || os.homedir();
}

async function runCommand(args, message) {
  const cwd = currentDir();
  const bin = resolveZhcBin();
  execFile(bin, args, { cwd }, (err, stdout, stderr) => {
    const tail = (stdout + stderr).trim().split('\n').slice(-3).join('\n');
    if (err) {
      vscode.window.showErrorMessage(message + '失败：' + tail || err.message);
    } else {
      vscode.window.showInformationMessage(message + '完成');
    }
  });
}

function convertFullwidth(editor, edit) {
  const text = editor.document.getText();
  const [converted, count] = convertFullwidthText(text);
  if (count > 0) {
    const full = new vscode.Range(0, 0, editor.document.lineCount, 0);
    edit.replace(full, converted);
    vscode.window.showInformationMessage('zhc：已转换 ' + count + ' 个全角标点（字符串内保留）');
  } else {
    vscode.window.showInformationMessage('zhc：没有需要转换的全角标点');
  }
}

// ---------- 激活 ----------

function activate(context) {
  const client = new ZhcLspClient();
  client.start();
  const ws = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  client.initialize(ws || null);

  // didOpen / didChange / didClose → 行帧转发（zhc 代理自跑 cjc 诊断）
  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument((doc) => {
      if (doc.languageId === 'zhc-dialect') client.didOpen(doc);
    }),
    vscode.workspace.onDidChangeTextDocument((ev) => {
      if (ev.document.languageId === 'zhc-dialect') client.didChange(ev.document);
    }),
    vscode.workspace.onDidCloseTextDocument((doc) => {
      if (doc.languageId === 'zhc-dialect') client.didClose(doc);
    })
  );

  // 全角自动转换（输入时；可配置关闭）
  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((ev) => {
      const cfg = vscode.workspace.getConfiguration('zhc');
      if (!cfg.get('autoConvertFullwidth')) return;
      const doc = ev.document;
      if (doc.languageId !== 'zhc-dialect') return;
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.document !== doc) return;
      for (const ch of ev.contentChanges) {
        if (!ch.text) continue;
        for (const c of ch.text) {
          if (FULLWIDTH_MAP[c]) {
            // 输入了全角标点 → 立即替换为半角（字符串内由命令级状态机保证跳过）
            const line = doc.lineAt(ch.range.start.line);
            const textBefore = line.text.slice(0, ch.range.start.character);
            const ranges = stringRanges(textBefore);
            const pos = textBefore.length - 1;
            if (!isInString(ranges, pos)) {
              const edit = new vscode.WorkspaceEdit();
              edit.replace(doc.uri, ch.range, FULLWIDTH_MAP[c]);
              vscode.workspace.applyEdit(edit);
            }
            break;
          }
        }
      }
    })
  );

  // 命令注册
  context.subscriptions.push(
    vscode.commands.registerCommand('zhc.run', () => {
      const doc = vscode.window.activeTextEditor && vscode.window.activeTextEditor.document;
      if (!doc) return;
      runInTerminal(['run', doc.fileName], path.dirname(doc.fileName));
    }),
    vscode.commands.registerCommand('zhc.check', () => {
      const doc = vscode.window.activeTextEditor && vscode.window.activeTextEditor.document;
      if (!doc) return;
      runInTerminal(['check', doc.fileName], path.dirname(doc.fileName));
    }),
    vscode.commands.registerCommand('zhc.add', async () => {
      const name = await vscode.window.showInputBox({ prompt: '库名（如 libdemo）', placeHolder: 'zhc add <库>' });
      if (!name) return;
      runCommand(['add', name], 'zhc add ');
    }),
    vscode.commands.registerTextEditorCommand('zhc.convertFullwidth', (editor, edit) => {
      convertFullwidth(editor, edit);
    })
  );

  context.subscriptions.push({ dispose: () => client.dispose() });
}

function deactivate() {}

module.exports = { activate, deactivate };
