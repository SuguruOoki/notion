--
-- ion/share/ioncore-bindings.lua
-- 
-- Copyright (c) Tuomo Valkonen 2004-2005.
--
-- Ion is free software; you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation; either version 2.1 of the License, or
-- (at your option) any later version.
--

local ioncore=_G.ioncore

local warn=ioncore.warn

local compiled2str=setmetatable({}, {__mode="k"})

--DOC
-- Compile string \var{cmd} into a bindable function. Within \var{cmd}, the
-- variable ''\var{_}'' (underscore) can be used to refer to the object 
-- that was selecting for the bound action and chosen to handle it.
-- The  variable ''\var{_sub}'' refers to a ''currently active'' sub-object 
-- of \var{_}, or a sub-object where the action loading to the binding 
-- being called actually occured.
-- 
-- The string \var{guard}  maybe set to pose limits on \code{_sub}. Currently 
-- supported guards are \code{_sub:non-nil} and \code{_sub:WFoobar}, where 
-- \type{WFoobar} is a class.
function ioncore.compile_cmd(cmd, guard)
    local guardcode=""
    if guard then
        local st, en, condition=string.find(guard, "^_sub:([%w-_]+)$")
        if not condition then
            warn(TR("Invalid guard %s.", guard))
        elseif condition=="non-nil" then
            guardcode='if not _sub then return end; '
        else
            guardcode='if not obj_is(_sub, "'..condition..'") then return end; '
        end
    end

    local gfncode="return function(_, _sub) "..guardcode.." return true end"
    local gfn, gerr=loadstring(gfncode)
    if not gfn then
        warn(TR("Error compiling guard: %s", gerr))
    end
    gfn=gfn()
    
    if type(cmd)=="string" then
        local fncode="return function(_, _sub) "..guardcode..cmd.." end"
        local fn, err=loadstring(fncode)
        if not fn then
            warn(TR("Error in command string: ", err))
            return
        end
        fn=fn()
        compiled2str[fn]=cmd
        return fn, gfn
    elseif type(cmd)=="function" then
        if gfn then
            return function(_, _sub) 
                       if gfn(_, _sub) then cmd(_, _sub) end 
                   end, gfn
        end
        return cmd
    end

    warn(TR("Invalid command"))
end


local function putcmd(cmd, guard, tab)
    local func
    if cmd then
        func=ioncore.compile_cmd(cmd, guard)
        if type(func)~="function" then
            return
        end
    end
    
    tab.func=func
    tab.cmdstr=cmd
    tab.guard=guard
    
    return tab
end

--DOC
-- Used to enter documentation among bindings so that other programs
-- can read it. Does nothing.
function ioncore.bdoc(text)
    return {action = "doc", text = text}
end

--DOC
-- Returns a function that creates a submap binding description table.
-- When the key press action \var{keyspec} occurs, Ioncore will wait for
-- a further key presse and act according to the submap.
-- For details, see section \ref{sec:bindings}.
function ioncore.submap(kcb_, list)
    if not list then
        return function(lst)
                   return submap(kcb_, lst)
               end
    end
    return {action = "kpress", kcb = kcb_, submap = list}
end

--DOC
-- Creates a binding description table for the action of pressing a key given 
-- by \var{keyspec} (with possible modifiers) to the function \var{func}.
-- For more information on bindings, see section \ref{sec:bindings}.
function ioncore.kpress(keyspec, cmd, guard)
    return putcmd(cmd, guard, {action = "kpress", kcb = keyspec})
end

--DOC
-- This is similar to \fnref{kpress} but after calling \var{cmd}, 
-- Ioncore waits for all modifiers to be released before processing
-- any further actions.
-- For more information on bindings, see section \ref{sec:bindings}.
function ioncore.kpress_wait(keyspec, cmd, guard)
    return putcmd(cmd, guard, {action = "kpress_waitrel", kcb = keyspec})
end

local function mact(act_, kcb_, cmd, guard)
    local st, en, kcb2_, area_=string.find(kcb_, "([^@]*)@(.*)")
    return putcmd(cmd, guard, {
        action = act_,
        kcb = (kcb2_ or kcb_),
        area = area_,
    })
end

--DOC
-- Creates a binding description table for the action of clicking a mouse 
-- button while possible modifier keys are pressed,
-- both given by \var{buttonspec}, to the function \var{func}.
-- For more information, see section \ref{sec:bindings}.
function ioncore.mclick(buttonspec, cmd, guard)
    return mact("mclick", buttonspec, cmd, guard)
end

--DOC
-- Similar to \fnref{mclick} but for double-click.
-- Also see section \ref{sec:bindings}.
function ioncore.mdblclick(buttonspec, cmd, guard)
    return mact("mdblclick", buttonspec, cmd, guard)
end

--DOC
-- Similar to \fnref{mclick} but for just pressing the mouse button.
-- Also see section \ref{sec:bindings}.
function ioncore.mpress(buttonspec, cmd, guard)
    return mact("mpress", buttonspec, cmd, guard)
end

--DOC
-- Creates a binding description table for the action of moving the mouse
-- (or other pointing device) while the button given by \var{buttonspec}
-- is held pressed and the modifiers given by \var{buttonspec} were pressed
-- when the button was initially pressed.
-- Also see section \ref{sec:bindings}.
function ioncore.mdrag(buttonspec, cmd, guard)
    return mact("mdrag", buttonspec, cmd, guard)
end

--DOC
-- Define bindings for context \var{context}. Here \var{binding} is
-- a table composed of entries created with \fnref{ioncore.kpress}, 
-- etc.; see section \ref{sec:bindings} for details.
function ioncore.defbindings(context, bindings)
    local function filterdoc(b)
        local t={}
        for k, v in ipairs(b) do
            local v2=v
            if v2.submap then
                v2=table.copy(v)
                v2.submap=filterdoc(v2.submap)
            end
            if v2.action~="doc" then
                table.insert(t, v2)
            end
        end
        return t
    end
    return ioncore.do_defbindings(context, filterdoc(bindings))
end

local function bindings_get_cmds(map)
    for k, v in map do
        if v.func then
            v.cmd=compiled2str[v.func]
        end
        if v.submap then
            bindings_get_cmds(v.submap)
        end
    end
end

--DOC
-- Get a table of all bindings.
function ioncore.getbindings(maybe_context)
    local bindings=ioncore.do_getbindings()
    if maybe_context then
        bindings_get_cmds(bindings[maybe_context])
        return bindings[maybe_context]
    else
        for k, v in bindings do
            bindings_get_cmds(v)
        end
        return bindings
    end
end

