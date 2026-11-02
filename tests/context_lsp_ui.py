"""Verify result-driven menus through a native LSP client and attached UI."""
import os
import signal
from rpc import Capture

signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError("LSP menu UI timed out")))
signal.alarm(30)
ui = Capture(os.environ.copy())


def lua(code):
    return ui.request("nvim_exec_lua", [code, []])


def keys(text):
    ui.request("nvim_input", [text])
    lua("return 1")


def click(row, col):
    ui.request("nvim_input_mouse", ["right", "press", "", 0, row, col])
    lua("return 1")
    ui.request("nvim_input_mouse", ["right", "release", "", 0, row, col])
    lua("return 1")


def screen():
    lua("vim.cmd('redraw!')")
    return "\n".join("".join(c for c, _ in row) for row in ui.grid)


def visible(name):
    return lua(f"for _,item in ipairs(menu.state().items) do if item.id=='{name}' then return true end end return false")


try:
    ui.request("nvim_ui_attach", [80, 24, {"rgb": True, "ext_linegrid": True}])
    lua("""
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.o.mouse='a'; vim.o.mousetime=0; vim.o.laststatus=0
      vim.wo.number=false; vim.wo.signcolumn='no'; vim.wo.foldcolumn='0'
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'no target here','symbol target'})
      source=vim.api.nvim_get_current_win(); source_buf=vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_name(source_buf,vim.fn.getcwd()..'/lsp-menu-fixture.lua')
      require('ui_tools').setup({context_menu=true})
      menu=require('ui_tools.context_menu')
      require('ui_tools.integrations.context_lsp').setup({
        actions={definition=function(ctx) invoked={win=vim.api.nvim_get_current_win(),cursor=ctx.cursor} end},
        shortcuts={definition='gd'},
      })
      pending={}; sequence=0
      native_client=vim.lsp.start({name='context-menu-fixture',
        cmd=function(dispatchers)
          local closed=false
          return {
            request=function(method,params,callback,on_reply)
              sequence=sequence+1; local id=sequence
              if method=='initialize' or method=='shutdown' then
                vim.schedule(function()
                  callback(nil,method=='initialize' and {capabilities={
                    positionEncoding='utf-16',definitionProvider=true,referencesProvider=true,
                    hoverProvider=true,renameProvider={prepareProvider=true},
                    codeActionProvider=true,documentFormattingProvider=true}} or nil)
                  if on_reply then on_reply(id) end
                end)
              else
                pending[method]={callback=callback,params=params,id=id,on_reply=on_reply}
              end
              return true,id
            end,
            notify=function(method)
              if method=='exit' then closed=true; dispatchers.on_exit(0,0) end
              return true
            end,
            is_closing=function() return closed end,
            terminate=function() closed=true; dispatchers.on_exit(0,0) end,
          }
        end,
      })
      assert(vim.wait(1000,function() return vim.lsp.get_client_by_id(native_client).initialized end))
      function respond(method,result,err)
        local request=assert(pending[method],method)
        pending[method]=nil
        request.callback(err,result)
        if request.on_reply then request.on_reply(request.id) end
      end
    """)
    click(0, 0)
    assert not visible("definition")
    assert visible("format")
    lua("""
      respond('textDocument/definition',vim.NIL)
      respond('textDocument/references',{})
      respond('textDocument/hover',{contents={kind='markdown',value=''}})
      respond('textDocument/prepareRename',vim.NIL)
      respond('textDocument/codeAction',{})
      vim.wait(20)
    """)
    for name in ("definition", "references", "hover", "rename", "code_action"):
        assert not visible(name), name
    assert "Go to definition" not in screen()
    keys("<Esc>")

    click(1, 2)
    assert not visible("definition")
    keys("<Down>")
    assert lua("local s=menu.state(); return s.items[s.selected].id") == "paste"
    # Delayed native responses arrive while the menu float has focus.
    lua("""
      local p=pending['textDocument/definition'].params
      assert(p.textDocument.uri==vim.uri_from_bufnr(source_buf))
      assert(p.position.line==1 and p.position.character==2)
      respond('textDocument/definition',{{uri=vim.uri_from_bufnr(source_buf),
        range={start={line=1,character=0},['end']={line=1,character=6}}}})
      respond('textDocument/references',{})
      respond('textDocument/hover',{contents={kind='markdown',value='Symbol documentation'}})
      respond('textDocument/prepareRename',nil,{code=-32602,message='Cannot rename'})
      respond('textDocument/codeAction',{{title='No fix',disabled={reason='unavailable'}}})
      vim.wait(20)
    """)
    assert visible("definition") and visible("hover")
    assert not visible("references") and not visible("rename") and not visible("code_action")
    assert lua("local s=menu.state(); return s.items[s.selected].id") == "paste"
    text = screen()
    assert "Go to definition" in text and "gd" in text and "Hover documentation" in text, text
    for _ in range(20):
        if lua("local s=menu.state(); return s.items[s.selected].id") == "definition":
            break
        keys("<Down>")
    keys("<CR>")
    assert lua("return menu.state()==nil and invoked.win==source and invoked.cursor[1]==2 and invoked.cursor[2]==2")
    lua("vim.lsp.get_client_by_id(native_client):stop(true); require('ui_tools').disable()")
    assert lua("return vim.tbl_count(menu.errors)") == 0
    print("context LSP UI: native client responses, empty targets, stable selection and action routing passed")
finally:
    ui.close()
    signal.alarm(0)
