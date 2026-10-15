"""Record only this installation's documentation, retaining concurrent WIP."""
from pathlib import Path
import difflib
import hashlib
import json
import subprocess

MOD = Path(__file__).resolve().parents[1]
GAME = MOD.parents[1]
RECEIPT = MOD/'build/out/keybind-client-installation/deployment.json'


def git(root, *args, data=None):
    result = subprocess.run(['git',*args],cwd=root,input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
    return result.stdout


def prefix(text, entry):
    if entry in text:
        return text
    if text.startswith('# '):
        title, tail = text.split('\n',1)
        return title+'\n\n'+entry+tail.lstrip('\n')
    return entry+text


def main():
    receipt=json.loads(RECEIPT.read_text(encoding='utf-8-sig'))
    assert receipt['status']=='installed-and-verified','Do not publish success before verification'
    commits={}
    for entry in receipt['clients']:
        root=GAME/'mods'/entry['mod']
        assert hashlib.sha256(Path(entry['target']).read_bytes()).hexdigest().upper()==entry['after'].upper(),'A later deployment changed the installed bytes'
        doc='state/keybind-deployment-2026-10-15.md'
        if (root/doc).exists():
            recorded=git(root,'show','HEAD:'+doc).decode('utf-8-sig')
            assert entry['after'] in recorded and receipt['installedAt'] in recorded,'An existing record belongs to a different installation'
            commits[entry['mod']]=git(root,'log','-1','--format=%H','--',doc).decode().strip()
            print(entry['mod'],commits[entry['mod']],'already recorded',flush=True)
            continue
        assert not git(root,'diff','--cached','--name-only').strip(),f"Index occupied: {entry['mod']}"
        head=git(root,'rev-parse','HEAD')
        note='> 2026-10-15 菜单改键已安装：本模组改键候选已随统一六客户端安装并从正式路径读回，七模组23项联合两进程346项通过。当前正式SHA256 '+entry['after']+'。入口「模组→对应模组→快捷键」，保存后重启游戏加载新版；本机偏好即时保存。备份/回退及权限见[keybind-deployment-2026-10-15.md](keybind-deployment-2026-10-15.md)。下方候选及旧安装记忆保留历史；未发布WIP没有带入本次安装。\n\n'
        journal='## 2026-10-15 菜单改键已部署并正式读回复验\n\n- 用户在快捷键统筹会话明确选择安装剩余六个客户端；备份后安装固定产物SHA256 '+entry['after']+'。\n- 正式路径原字节复制到唯一AIR应用，七模组23项联合175＋171项通过；原本体/清单/配置及其它模块指纹复核无变。没有关闭玩家游戏或写真实存档。\n- 本模组旧文件SHA256 '+entry['before']+'，备份 '+entry['backup'].replace('\\','/')+'。安装与统一回退见state/keybind-deployment-2026-10-15.md；保留其他任务WIP。\n\n'
        patch=''
        for rel, addition in [('state/MEMORY.md',note),('state/journal.md',journal)]:
            before=git(root,'show','HEAD:'+rel).decode('utf-8-sig').replace('\r\n','\n')
            path=root/rel
            current=path.read_bytes()
            working=current.decode('utf-8-sig').replace('\r\n','\n')
            assert path.read_bytes()==current,'Concurrent document update; retry after inspection'
            path.write_text(prefix(working,addition),encoding='utf-8')
            desired=prefix(before,addition)
            patch+=''.join(difflib.unified_diff(before.splitlines(True),desired.splitlines(True),fromfile='a/'+rel,tofile='b/'+rel))
        content='# 菜单改键统一部署（2026-10-15）\n\n已安装并验证。用户在统筹会话01a13f40-6ca2-7872-9f9a-c1e453e80745明确选择“安装剩余六个（推荐）”。本记录只确认改键部署，不发布源码目录其他实验。\n\n- 正式文件：'+entry['target'].replace('\\','/')+'\n- 安装SHA256：`'+entry['after']+'`\n- 原文件SHA256：`'+entry['before']+'`\n- 精确备份：'+entry['backup'].replace('\\','/')+'\n- 源候选：'+entry['source'].replace('\\','/')+'\n\n安装时间：'+receipt['installedAt']+'。正式ModLoader BD71、FA B330与七客户端共同读回验证：首进程175项、重启171项；本模组改键按钮、精确组合、显示宽高、跨进程保存和默认恢复通过。各客户端更深入的实际动作验证保留在keybind-integration-2026-10-15.md，不把联合计数当作全部战斗或DLC验收。\n\n统一回执：../../ModLoader/build/out/keybind-client-installation/deployment.json；稳定证据及说明：../../ModLoader/state/keybind-integration-2026-10-15.md。回退在游戏退出后调用ModLoader/build/deploy-keybind-clients.ps1 -Action Rollback，先核对六个目标仍为此次指纹，禁止覆盖后续部署。若出现更晚安装，应按更新的部署回执协调回退，不直接复制旧备份。\n\n源码中未发布的B、墙面/曳光或灯光优化保持各自WIP所有权；后续版本须保留本轮按键适配器和菜单。此部署未改用户真实存储与加载清单，没有强制重启玩家实例，重启游戏后生效。\n'
        assert not (root/doc).exists(),'Deployment record already exists; inspect before replacing'
        (root/doc).write_text(content,encoding='utf-8')
        assert git(root,'rev-parse','HEAD')==head,'Concurrent commit; inspect before staging'
        if patch:
            git(root,'apply','--cached','--check','--whitespace=nowarn','-',data=patch.encode('utf-8'))
            git(root,'apply','--cached','--whitespace=nowarn','-',data=patch.encode('utf-8'))
        git(root,'add','--',doc)
        expected={'state/MEMORY.md','state/journal.md',doc}
        release_rel='release/'+entry['file']
        tracked=subprocess.run(['git','ls-files','--error-unmatch','--',release_rel],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE).returncode==0
        if tracked:
            # Repositories that already track their deployed artifact keep it
            # with this release commit; ignored artifacts remain untracked.
            git(root,'add','--',release_rel)
            expected.add(release_rel)
        actual=set(git(root,'diff','--cached','--name-only').decode().splitlines())
        assert actual<=expected, f'Unexpected staged files: {actual-expected}'
        git(root,'diff','--cached','--check')
        git(root,'-c','user.name=eclipse','-c','user.email=helloimyyt@163.com','commit','-m','部署: 安装并复验模组菜单改键')
        commits[entry['mod']]=git(root,'rev-parse','HEAD').decode().strip()
        print(entry['mod'],commits[entry['mod']],flush=True)
    (RECEIPT.parent/'recorded-commits.json').write_text(json.dumps(commits,ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()
