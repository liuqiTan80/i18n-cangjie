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
//   6. 词表补全/悬停（lib/zhc-words.json，tools/gen_words.py 从语言包生成，
//      本地零依赖；函数类词条补全自动带 () 光标居中，宏补全带 @ 前缀）
//
// zhc 可执行文件解析（跨平台）：配置 zhc.binPath → 环境变量 ZHC_BIN → PATH 扫描
// （Windows 按 PATHEXT 后缀探测）→ 用户主目录 ~/.zhc 回退。

const vscode = require('vscode');
const { spawn, execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
// 全角转换词法状态机 + 词表纯逻辑（lib/ 下无 vscode 依赖，node 单测覆盖）
const { FULLWIDTH_MAP, inStringInsert, convertFullwidthText } = require('./lib/fullwidth');
const wordsLib = require('./lib/words.js');

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
  // 诊断输出通道（转换异常/原因可见，便于用户反馈与排查）
  const log = vscode.window.createOutputChannel('zhc 输入');
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

  // 词表补全/悬停的 kind 描述与 VS Code 图标映射
  const KIND_LABEL = {
    keyword: '关键字', type: '类型', function: '函数', literal: '字面量',
    module: '模块路径', macro: '宏（@ 前缀）',
  };
  const KIND_VSC = {
    keyword: vscode.CompletionItemKind.Keyword, type: vscode.CompletionItemKind.Class,
    function: vscode.CompletionItemKind.Function, literal: vscode.CompletionItemKind.Value,
    module: vscode.CompletionItemKind.Module, macro: vscode.CompletionItemKind.Function,
  };

  // 输入时自动转换：不立即改文档，而是延迟 60ms 统一处理——Linux IME 对一次上屏
  // 常连发两次编辑事件（组合提交分两段 commit），立即 applyEdit 会与第二段提交
  // 竞态，形成「转出的半角 + 第二段上屏的全角」并排重复。延迟后以事件位置为中心
  // 窄窗口重新扫描，命中即替换（已转则窗口无全角 → 幂等空转，天然防重复）
  // 调度去重：同 key（IME 双发同内容）或 250ms 内同行相邻位置（IME 分两段 commit
  // 的相邻字符）只保留一个调度——convertAt 的 ±2 窗口会一并扫描覆盖
  let pending = { key: '', line: -1, char: -1, t: 0 };

  /** 延迟执行的幂等转换：扫描事件点 ±2 字符窗口内的全角标点，全部替换为半角 */
  function convertAt(log, doc, editor, anchor) {
    try {
      const lineText = doc.lineAt(anchor.line).text;
      if (anchor.character > lineText.length) return;
      const from = Math.max(0, anchor.character - 2);
      const to = Math.min(lineText.length, anchor.character + 3);
      const hits = [];
      for (let i = from; i < to; i++) {
        const c = lineText[i];
        if (FULLWIDTH_MAP[c]) hits.push({ i, c });
      }
      if (hits.length === 0) return;   // 已被上一轮调度处理 → 幂等
      log.appendLine('[转换] @' + anchor.line + ':' + anchor.character + ' 命中 '
        + hits.map((h) => JSON.stringify(h.c)).join(''));
      const edit = new vscode.WorkspaceEdit();
      if (hits.length === 1 && hits[0].c === '（') {
        // 单个全角开括号（输入法未自动补闭括号）：转为 () 且光标停在中间
        edit.replace(doc.uri, new vscode.Range(anchor.line, hits[0].i, anchor.line, hits[0].i + 1), '()');
        vscode.workspace.applyEdit(edit).then(() => {
          const mid = new vscode.Position(anchor.line, hits[0].i + 1);
          editor.selection = new vscode.Selection(mid, mid);
        });
      } else {
        for (const h of hits) {
          edit.replace(doc.uri, new vscode.Range(anchor.line, h.i, anchor.line, h.i + 1), FULLWIDTH_MAP[h.c]);
        }
        vscode.workspace.applyEdit(edit);
      }
    } catch (e) {
      log.appendLine('[转换异常] ' + (e && e.stack || e));
      log.show(true);
    }
  }

  // 全角自动转换 + IME 上屏补全触发（输入时；可配置关闭）
  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((ev) => {
      const cfg = vscode.workspace.getConfiguration('zhc');
      const doc = ev.document;
      if (doc.languageId !== 'zhc-dialect') return;
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.document !== doc) return;
      const now = Date.now();
      try {
        for (const ch of ev.contentChanges) {
          if (!ch.text || ch.range.start.line !== ch.range.end.line) continue;
          const text = ch.text;
          // ① IME 上屏中文/敲 @：VS Code 对上屏文本不自动弹补全，手动触发
          //    （词表有该前缀匹配才弹，避免空列表打扰）
          if (text === '@' ||
              (/^[\p{Script=Han}]+$/u.test(text) && wordsLib.allWords().some((w) => w.zh.startsWith(text)))) {
            const delay = text === '@' ? 80 : 40;   // @ 的 VS Code 自动触发与手动触发易叠，稍候再弹
            setTimeout(() => {
              const e = vscode.window.activeTextEditor;
              if (e && e.document === doc && doc === vscode.window.activeTextEditor.document) {
                log.appendLine('[补全] 已弹补全：' + text);
                vscode.commands.executeCommand('editor.action.triggerSuggest');
              }
            }, delay);
            continue;
          }
          // ② 全角转换：仅处理由映射字符组成的整段上屏（单标点或输入法智能成对 （））
          if (!cfg.get('autoConvertFullwidth')) continue;
          const chars = [...text];
          if (chars.length === 0 || !chars.every((c) => FULLWIDTH_MAP[c] !== undefined)) continue;
          const lineText = doc.lineAt(ch.range.start.line).text;
          const prefix = lineText.slice(0, ch.range.start.character);
          // 字符串/注释内保留（inStringInsert：含未闭合字符串行尾继续输入的场景）
          if (inStringInsert(prefix, prefix.length)) continue;
          // 双发事件只调度一次；延迟统一处理规避竞态
          const key = ch.range.start.line + ':' + ch.range.start.character + ':' + text;
          const adjacent = pending.line === ch.range.start.line
            && Math.abs(pending.char - ch.range.start.character) <= 2 && now - pending.t < 250;
          if (pending.key === key || adjacent) continue;
          pending = { key, line: ch.range.start.line, char: ch.range.start.character, t: now };
          log.appendLine('[输入] ' + JSON.stringify(text) + ' @' + key + ' → 调度转换');
          setTimeout(() => convertAt(log, doc, editor, ch.range.start), 60);
          break;
        }
      } catch (e) {
        log.appendLine('[自动转换异常] ' + (e && e.stack || e));
        log.show(true);
      }
    })
  );

  // 词表联想补全（zhc-words.json 本地词表；函数类自动带 ()，宏自动带 @）
  // '@' 为宏触发字符（@ 非词字符，不触发联想）：键入 @ 即弹宏词条列表
  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider('zhc-dialect', {
      provideCompletionItems(document, position) {
        const lineText = document.lineAt(position.line).text;
        const m = lineText.slice(0, position.character).match(/[\p{L}\p{N}_@]*$/u);
        const prefix = m ? m[0] : '';
        // 输入 @ 只列宏词条（方言宏书写为 @派生/@测试…）
        const words = prefix === '@'
          ? wordsLib.allWords().filter((w) => w.kind === 'macro')
          : wordsLib.matchPrefix(prefix);
        log.appendLine('[补全请求] prefix=' + JSON.stringify(prefix) + ' → ' + words.length + ' 条');
        return words.map((w) => {
          const item = new vscode.CompletionItem(w.zh, KIND_VSC[w.kind] || vscode.CompletionItemKind.Text);
          // 显式替换范围 = 光标前的词 token（中文词/官方名/@ 宏）：不设置时 VS Code
          // 对 IME 上屏文本可能按空范围插入，出现「打打印行()」式前缀残留
          if (m) item.range = new vscode.Range(position.line, m.index, position.line, position.character);
          item.detail = w.en;   // 官方原名副标题
          item.documentation = new vscode.MarkdownString(
            `对应 \`${w.en}\`\n\n${KIND_LABEL[w.kind] || w.kind}${w.cat && w.cat !== '标识符' ? '（' + w.cat + '）' : ''}词条`);
          item.sortText = String((wordsLib.KIND_ORDER[w.kind] || 9)) + w.zh;
          if (w.kind === 'function') {
            // 函数词条：补全即带 () 且光标居中
            item.insertText = new vscode.SnippetString(`${w.zh}($0)`);
          } else if (w.kind === 'macro') {
            item.insertText = `@${w.zh}`;
          } else {
            item.insertText = w.zh;
          }
          return item;
        });
      },
    }, '@')
  );

  // 悬停释义：光标落在中文词（或混编官方词）上显示对应关系
  context.subscriptions.push(
    vscode.languages.registerHoverProvider('zhc-dialect', {
      provideHover(document, position) {
        const token = wordsLib.tokenAtLine(document.lineAt(position.line).text, position.character);
        if (!token) return null;
        const w = token.startsWith('@')
          ? wordsLib.findByZh(token.slice(1))
          : (wordsLib.findByZh(token) || wordsLib.findByEn(token));
        if (!w) return null;
        const kindCn = KIND_LABEL[w.kind] || w.kind;
        const md = new vscode.MarkdownString();
        if (w.kind === 'macro') {
          md.appendMarkdown(`**@${w.zh}** 宏 · 对应 \`@${w.en}\``);
        } else {
          md.appendMarkdown(`**${w.zh}** ${kindCn} · 对应 \`${w.en}\``);
        }
        if (w.kind === 'function') {
          md.appendMarkdown('\n\n补全时自动带括号：`' + w.zh + '()`');
        }
        return new vscode.Hover(md);
      },
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

  context.subscriptions.push({ dispose: () => { client.dispose(); log.dispose(); } });
}

function deactivate() {}

module.exports = { activate, deactivate };
