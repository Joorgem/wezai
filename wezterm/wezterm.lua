local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()

local home = os.getenv('USERPROFILE') or os.getenv('HOME') or ''
local wezterm_dir = home .. '\\.config\\wezterm'
local wezterm_bashrc = wezterm_dir .. '\\bashrc.wezterm'

-- github_dir: override via GITHUB_DIR env var (matches repo-launcher.sh behaviour)
local github_dir = os.getenv('GITHUB_DIR') or (home .. '\\Documents\\github')

-- git_bash: override via WEZAI_GIT_BASH, else try common install locations
local function find_git_bash()
  local candidates = {
    'C:\\Program Files\\Git\\bin\\bash.exe',
    home .. '\\AppData\\Local\\Programs\\Git\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
  }
  for _, path in ipairs(candidates) do
    local f = io.open(path, 'r')
    if f then f:close(); return path end
  end
  return candidates[1]  -- fallback even if missing; WezTerm will surface a clear error
end

local git_bash = os.getenv('WEZAI_GIT_BASH') or find_git_bash()

local function append_windows_path(path_value, extra)
  local lower_path = path_value:lower()
  local lower_extra = extra:lower()
  if lower_path:find(lower_extra, 1, true) then
    return path_value
  end
  if path_value == '' then
    return extra
  end
  return path_value .. ';' .. extra
end

config.front_end = 'OpenGL'
config.max_fps = 60
config.animation_fps = 1

config.default_prog = { git_bash, '--rcfile', wezterm_bashrc, '-i' }
config.set_environment_variables = {
  CLAUDE_CODE_GIT_BASH_PATH = git_bash,
  PATH = append_windows_path(os.getenv('PATH') or '', wezterm_dir),
}

config.initial_cols = 200
config.initial_rows = 50

wezterm.on('gui-startup', function()
  local tab, pane, window = mux.spawn_window {
    cwd = github_dir,
  }

  pcall(function()
    tab:set_title('repos')
  end)

  wezterm.time.call_after(0.2, function()
    pane:send_text('repos\n')
    pane:activate()
  end)

  wezterm.time.call_after(0.5, function()
    local gui_window = window:gui_window()
    local screen = wezterm.gui.screens().active
    local dim = gui_window:get_dimensions()
    gui_window:set_position(
      (screen.width - dim.pixel_width) / 2,
      (screen.height - dim.pixel_height) / 2
    )
  end)
end)

config.color_scheme = 'Catppuccin Mocha'
config.font = wezterm.font_with_fallback {
  { family = 'JetBrains Mono', weight = 'Medium' },
  'JetBrainsMono Nerd Font',
}
config.font_size = 13.0
config.window_background_opacity = 1.0
config.window_padding = { left = 8, right = 8, top = 4, bottom = 4 }

config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 32
config.window_frame = {
  font = wezterm.font('JetBrains Mono', { weight = 'Medium' }),
  font_size = 9.0,
}

wezterm.on('format-tab-title', function(tab)
  local cwd = tab.active_pane.current_working_dir
  local title = tab.active_pane.title
  if cwd then
    title = cwd.file_path:match('([^/\\]+)/?$') or title
  end
  local index = tab.tab_index + 1
  return string.format(' %d - %s ', index, title)
end)

local git_cache = { branch = '', updated = 0 }

wezterm.on('update-right-status', function(window, pane)
  pcall(function()
    local cells = {}

    for _, battery in ipairs(wezterm.battery_info()) do
      local charge = math.floor(battery.state_of_charge * 100 + 0.5)
      local icon = '\u{f240}'
      if charge < 25 then
        icon = '\u{f243}'
      elseif charge < 50 then
        icon = '\u{f242}'
      elseif charge < 75 then
        icon = '\u{f241}'
      end

      local color = '#a6e3a1'
      if charge < 20 then
        color = '#f38ba8'
      elseif charge < 40 then
        color = '#fab387'
      end

      table.insert(cells, { Foreground = { Color = color } })
      table.insert(cells, { Text = icon .. ' ' .. charge .. '%' })
      table.insert(cells, { Foreground = { Color = '#585b70' } })
      table.insert(cells, { Text = '  |  ' })
    end

    local now = os.time()
    if now - git_cache.updated >= 5 then
      git_cache.branch = ''
      local cwd = pane:get_current_working_dir()
      if cwd then
        local success, stdout = wezterm.run_child_process {
          'git', '-C', cwd.file_path, 'branch', '--show-current'
        }
        if success and stdout then
          git_cache.branch = stdout:gsub('%s+', '')
        end
      end
      git_cache.updated = now
    end

    if git_cache.branch ~= '' then
      table.insert(cells, { Foreground = { Color = '#89b4fa' } })
      table.insert(cells, { Text = '\u{e0a0} ' .. git_cache.branch })
      table.insert(cells, { Foreground = { Color = '#585b70' } })
      table.insert(cells, { Text = '  |  ' })
    end

    table.insert(cells, { Foreground = { Color = '#7f849c' } })
    table.insert(cells, { Text = wezterm.strftime('%Y-%m-%d  %H:%M') .. '  ' })

    window:set_right_status(wezterm.format(cells))
  end)
end)

config.scrollback_lines = 10000
config.treat_left_ctrlalt_as_altgr = true

config.keys = {
  { key = 'Enter', mods = 'SHIFT', action = wezterm.action.SendString '\x1b[13;2u' },

  { key = 'c', mods = 'CTRL', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL', action = wezterm.action.PasteFrom 'Clipboard' },

  { key = 'v', mods = 'ALT|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'ALT|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },

  { key = 'LeftArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Down' },

  { key = 's', mods = 'ALT|SHIFT', action = wezterm.action.PaneSelect { mode = 'SwapWithActiveKeepFocus' } },
  { key = 'LeftArrow', mods = 'ALT|SHIFT', action = wezterm.action.RotatePanes 'CounterClockwise' },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = wezterm.action.RotatePanes 'Clockwise' },

  { key = 't', mods = 'CTRL|SHIFT', action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true } },

  {
    key = 'r',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.PromptInputLine {
      description = 'Tab name:',
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:active_tab():set_title(line)
        end
      end),
    },
  },
}

config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = wezterm.action.PasteFrom 'Clipboard',
  },
}

return config
