-- =====================================================================
-- SMC-PAD Pocket → 左手デバイス設定 (Hammerspoon)
-- =====================================================================
-- 16パッド(4×4)。ノート 36〜51、MIDI ch9。ノブ・フェーダーは無し。
-- パッドの並びは MPC/ドラム式で、ノート36が左下・行ごとに上へ上がる。
--
-- 再読み込み: Hammerspoonコンソールで hs.reload()
-- =====================================================================

-- ▼▼▼ 環境に合わせて変更する箇所 ▼▼▼ -----------------------------------

-- デバッグ: true にすると受信した全MIDIメッセージをコンソールに出力する。
-- これでデバイス名・パッドのノート番号を確認できる。確認が済んだら false に戻す。
local DEBUG = false

-- デバイスを識別する名前（部分一致）。DEBUG出力で実際の名前を確認して合わせる。
local DEVICE_MATCH = "SMC-PAD"

-- ---------------------------------------------------------------------
-- アプリ定義
-- ---------------------------------------------------------------------
-- bundleIDs を上から順に試し、見つからなければ name（アプリ名）でフォールバックする。
-- bundle ID はアプリ名の言語設定やリネームに影響されないので、こちらを優先する。
-- そのMacに入っていないアプリのパッドは、押してもログを出すだけで他に影響しない。
--
-- bundle ID の調べ方: osascript -e 'id of app "Slack"'
local APPS = {
  vscode     = { name = "Visual Studio Code", bundleIDs = { "com.microsoft.VSCode" } },
  pycharm    = { name = "PyCharm",            bundleIDs = { "com.jetbrains.pycharm",         -- Professional
                                                            "com.jetbrains.pycharm.ce" } },  -- Community
  excel      = { name = "Microsoft Excel",    bundleIDs = { "com.microsoft.Excel" } },
  sourcetree = { name = "Sourcetree",         bundleIDs = { "com.torusknot.SourceTreeNotMAS" } },
  slack      = { name = "Slack",              bundleIDs = { "com.tinyspeck.slackmacgap" } },
  browser    = { name = "Google Chrome",      bundleIDs = { "com.google.Chrome" } },
  claude     = { name = "Claude",             bundleIDs = { "com.anthropic.claudefordesktop" } },
  notes      = { name = "Notes",              bundleIDs = { "com.apple.Notes" } },
  powerpoint = { name = "Microsoft PowerPoint", bundleIDs = { "com.microsoft.Powerpoint" } },  -- スライド送り / ⌥Return 用
  word       = { name = "Microsoft Word",     bundleIDs = { "com.microsoft.Word" } },        -- ⌥Return 用
}

-- ---------------------------------------------------------------------
-- キーボードショートカット（ウィンドウ操作）
-- ---------------------------------------------------------------------
local MOD = { "alt" }  -- 修飾キー（⌥）

-- ⌥+キー → ウィンドウ操作
local WINDOW_KEYS = {
  left     = "9",  -- 左に配置。続けて押すと幅が 1/2 → 2/3 → 1/3
  right    = "0",  -- 右に配置。続けて押すと幅が 1/2 → 2/3 → 1/3
  maximize = "=",  -- 最大化
  restore  = "-",  -- 元の大きさに戻す
  grid     = "g",  -- グリッドで手動配置
  minimize = "m",  -- 最小化（直後にもう一度押すと元に戻す）
}

-- ⌥G のグリッドのマス目（横x縦）
local GRID_SIZE = "6x4"

-- Word / Excel / PowerPoint が前面のときだけ、⌥+このキーで F2 を送る（Excel ならセル内編集）
local OFFICE_EDIT_KEY = "return"

-- ▲▲▲ 変更箇所ここまで ▲▲▲ ------------------------------------------

-- ---------------------------------------------------------------------
-- アプリの解決 / 起動
-- ---------------------------------------------------------------------

-- 起動中のアプリを取得する（bundle ID 優先、無ければアプリ名）。未起動なら nil。
local function runningApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    local app = hs.application.get(id)
    if app then return app end
  end
  return hs.application.get(spec.name)
end

-- アプリを起動する（bundle ID を順に試し、最後にアプリ名でフォールバック）。
local function launchApp(spec)
  for _, id in ipairs(spec.bundleIDs or {}) do
    if hs.application.launchOrFocusByBundleID(id) then return true end
  end
  if hs.application.launchOrFocus(spec.name) then return true end
  print("[pad] 起動できない: " .. spec.name .. "（このMacに未インストール？）")
  return false
end

-- ---------------------------------------------------------------------
-- ウィンドウ列挙（別デスクトップ対応）
-- ---------------------------------------------------------------------
-- macOS は「今いるデスクトップ（スペース）のウィンドウ」しかアクセシビリティAPIで列挙できない。
-- Hammerspoon のドキュメントにも hs.window.allWindows() は "can only return windows in the
-- current Mission Control Space" と明記されている。実機でも、別デスクトップへ動かした
-- ウィンドウは app:allWindows() から消える（2枚開いていても現スペースの1枚しか見えない）。
--
-- hs.window.filter は一度認識したウィンドウをキャッシュし続けるので、別デスクトップにある
-- ウィンドウも返せる（AX参照は生きているのでフォーカスもできる）。これを一次ソースにし、
-- キャッシュに入る前のウィンドウは app:allWindows() で補完する。
--
-- 制約: Hammerspoon 起動より前から別デスクトップに置きっぱなしのウィンドウは、
-- そのデスクトップを一度表示するまで捕捉できない（表示した時点で登録される）。
-- これは macOS 側の制約なので回避手段は無い。実運用では Hammerspoon がログインから
-- 常駐しているため、普通に使っているうちに全デスクトップが捕捉済みになる。

-- デスクトップを切り替えるたびに全アプリのウィンドウを取り直す。
-- これが false（既定）だと、切り替え先で初めて見るウィンドウが登録されず、
-- 「別デスクトップのウィンドウが巡回対象に出てこない」状態が続く。
hs.window.filter.forceRefreshOnSpaceChange = true

-- 対象アプリのウィンドウに適用する条件。
-- visible / currentSpace は「省略 = 条件にしない」なので、最小化されたウィンドウも、
-- 別デスクトップのウィンドウも対象に入る。
--
-- setOverrideFilter は使わないこと。あれは「アプリ別ルールより前に全アプリへ適用」される、
-- つまり hs.window.filter が既定で除外しているアプリ（Hammerspoon 自身を含む）まで
-- 追跡対象に復活させてしまう。実機ではそれが原因で、Hammerspoon 自身のウィンドウに対して
-- "Unable to fetch NSRunningApplication for pid" がコンソールに出ていた。
local WINDOW_FILTER = { allowRoles = "AXStandardWindow" }

-- keepActive() は必須。これが無いと（passiveモードだと）getWindows() のたびに内部で
-- start → pause が走り、pause が stopGlobalWatcher() でウィンドウキャッシュを丸ごと破棄する。
-- 結果、毎回「今のデスクトップのウィンドウ」だけを数え直すことになり、別デスクトップの
-- ウィンドウが巡回対象から消える（実機で確認済み: 2/2 → 1/1 に戻ってしまう）。

-- 保温役: ウィンドウは1つも通さない空フィルタ（new(false) = 全拒否）。
-- 目的はウィンドウの取得ではなく、「Hammerspoon 起動中ずっと追跡を止めない」こと。
-- これが常時アクティブな限り、デスクトップを表示するたびに、そこのウィンドウが
-- Hammerspoon 内部のキャッシュへ登録されていく。
local windowWarmer = hs.window.filter.new(false, "smcpad.warm")
windowWarmer:keepActive()

-- アプリ名 → そのアプリ専用フィルタ。初回参照時に作る（保温キャッシュを引き継ぐので冷えない）。
-- 対象アプリだけを許可することで、全ウィンドウを走査して w:application() を呼ぶ必要がなくなる。
local appFilters = {}

local function filterForApp(app)
  local name = app:name()
  if not name then return nil end
  if not appFilters[name] then
    local wf = hs.window.filter.new(false, "smcpad.wf." .. name)  -- 既定は全拒否
    wf:setAppFilter(name, WINDOW_FILTER)                          -- このアプリだけ許可
    wf:keepActive()
    appFilters[name] = wf
  end
  return appFilters[name]
end

-- 対象アプリの通常ウィンドウを、ウィンドウID順（＝押すたびに変わらない安定した並び）で返す。
-- 最小化されたウィンドウ・別デスクトップのウィンドウも巡回対象に含める。
local function standardWindows(app)
  local seen, wins = {}, {}

  local function add(w)
    local id = w and w:id()
    if id and not seen[id] then
      seen[id] = true
      wins[#wins + 1] = w
    end
  end

  local wf = filterForApp(app)
  if wf then
    for _, w in ipairs(wf:getWindows()) do add(w) end   -- 別デスクトップ含む
  end
  for _, w in ipairs(app:allWindows()) do               -- 現デスクトップ分の取りこぼしを補完
    if w:isStandard() then add(w) end
  end

  table.sort(wins, function(a, b) return a:id() < b:id() end)
  return wins
end

-- ---------------------------------------------------------------------
-- フォーカス / ウィンドウ巡回
-- ---------------------------------------------------------------------

-- 「ウインドウ」メニューの名前。アプリや言語設定で表記が違うので、上から順に探す。
local WINDOW_MENU_NAMES = { "ウインドウ", "ウィンドウ", "Window" }

-- アプリの「ウインドウ」メニューにあるウィンドウ一覧から、win をタイトルで選ぶ。選べたら true。
-- 手でこのメニューから選んだときと同じく、別デスクトップのウィンドウならそこへ移動する。
-- 同じタイトルが複数あると上にある方が選ばれる。
local function selectFromWindowMenu(app, win)
  local title = win:title()
  if not title or title == "" then return false end
  for _, menu in ipairs(WINDOW_MENU_NAMES) do
    if app:selectMenuItem({ menu, title }) then return true end
  end
  return false
end

-- ウィンドウをフォーカスする。別デスクトップ（スペース）への移動は macOS 自身にさせる。
--   別アプリから切り替えるとき → win:focus() だけ。アプリの切り替えで macOS が移動してくれる。
--   同じアプリの中で巡回するとき → アプリの切り替えにならないので macOS は移動しない。
--                                   代わりに「ウインドウ」メニューから選んで移動させる。
--
-- 前提: システム設定 → デスクトップとDock →「アプリケーションの切り替えで、アプリケーションの
-- ウインドウが開いているスペースに移動」をオンにする（macOS の既定はオフ）。
--
-- hs.spaces.gotoSpace は使わないこと。あれは裏で Mission Control を開いてボタンをクリックする
-- 方式で、macOS 27 では "unable to get Mission Control data from the Dock" で失敗する
-- （macOS 26 までは動いていた）。
local function focusWindow(win)
  if win:isMinimized() then win:unminimize() end

  local spaces = hs.spaces.windowSpaces(win) or {}
  local screen = win:screen()
  local activeSpace = screen and hs.spaces.activeSpaceOnScreen(screen)

  local onActiveSpace = false
  for _, s in ipairs(spaces) do
    if s == activeSpace then onActiveSpace = true break end
  end

  -- 別デスクトップにある、前面アプリ自身のウィンドウ → ウインドウメニューから選ぶ
  if not onActiveSpace and spaces[1] and activeSpace then
    local app = win:application()
    local front = hs.application.frontmostApplication()
    if app and front and front:pid() == app:pid() and selectFromWindowMenu(app, win) then
      return
    end
  end
  win:focus()
end

-- そのアプリの「今フォーカスしているウィンドウの次」へ移動する。
-- 最後のウィンドウまで行ったら先頭に戻る（リング巡回）。
-- screen を渡すと、そのモニターにあるウィンドウだけを巡回する（別デスクトップ分も含む）。
local function cycleWindows(app, screen)
  local wins = standardWindows(app)
  if screen then
    local onScreen = {}
    for _, w in ipairs(wins) do
      local s = w:screen()
      if s and s:id() == screen:id() then onScreen[#onScreen + 1] = w end
    end
    wins = onScreen
  end
  if #wins == 0 then return false end

  local current = hs.window.focusedWindow()
  local idx = 0  -- 0 = 対象アプリのウィンドウにフォーカスしていない → 先頭から
  if current then
    for i, w in ipairs(wins) do
      if w:id() == current:id() then idx = i break end
    end
  end

  local nextIdx = idx % #wins + 1
  focusWindow(wins[nextIdx])
  print(string.format("[pad] %s ウィンドウ %d/%d", app:name(), nextIdx, #wins))
  return true
end

-- パッドを押したときの挙動:
--   未起動           → 起動する
--   起動中・非最前面 → そのアプリへフォーカス（直前に使っていたウィンドウが出る）
--   起動中・最前面   → 同じアプリの次のウィンドウへ巡回（複数ウィンドウを開いているとき）
local function focus(spec)
  return function()
    local app = runningApp(spec)
    if not app then
      launchApp(spec)
      return
    end

    local front = hs.application.frontmostApplication()
    if front and front:pid() == app:pid() then
      if cycleWindows(app) then return end   -- 既に最前面 → 次のウィンドウへ
    else
      -- 直前に使っていたウィンドウ（mainWindow）を focusWindow 経由で前面に出す。
      local win = app:mainWindow() or standardWindows(app)[1]
      if win then
        focusWindow(win)
        return
      end
    end

    launchApp(spec)  -- ウィンドウが1枚も無い（全部閉じている等）→ 起動しなおして開かせる
  end
end

-- 前面アプリのウィンドウのうち、今のモニターにあるものだけを巡回する（別デスクトップ分も含む）。
-- アプリのパッドは全モニターのウィンドウを巡回するので、こちらはモニターを絞って役割を分けている。
local function cycleFrontmostOnScreen()
  local app = hs.application.frontmostApplication()
  local current = hs.window.focusedWindow()
  local screen = (current and current:screen()) or hs.mouse.getCurrentScreen()
  if app and screen then cycleWindows(app, screen) end
end

-- ---------------------------------------------------------------------
-- ウィンドウ配置
-- ---------------------------------------------------------------------
-- 配置に使う領域: メニューバーの下から画面の端まで（Dock は自動で隠す前提で、その分は空けない）。
-- それでも下端まで伸びないときは macOS が古い領域を返している。`killall Dock` で直る。
local function workArea(screen)
  local full, f = screen:fullFrame(), screen:frame()
  return { x = full.x, y = f.y, w = full.w, h = full.y + full.h - f.y }
end

-- 「元の大きさ」（⌥-）に戻せるよう、本設定で動かす前の位置と大きさをウィンドウごとに覚えておく。
-- 続けて配置を変えても最初の位置を保つ。ただし本設定で動かした後に手で動かしていれば、
-- その位置を新しい「元の大きさ」とする。パッドとショートカットのどちらで動かしても記録する。
local originalFrame = {}  -- ウィンドウID → 本設定で動かす前の位置と大きさ
local placedFrame   = {}  -- ウィンドウID → 本設定が最後に置いた位置と大きさ

local function copyFrame(f)
  return { x = f.x, y = f.y, w = f.w, h = f.h }
end

-- ターミナル等は文字単位でしかリサイズできないので、多少のずれは同じ位置とみなす
local TOLERANCE = 20

local function near(f, t)
  return math.abs(f.x - t.x) <= TOLERANCE and math.abs(f.y - t.y) <= TOLERANCE
    and math.abs(f.w - t.w) <= TOLERANCE and math.abs(f.h - t.h) <= TOLERANCE
end

-- 配置を変える直前に呼ぶ。元の位置と大きさを覚える
local function remember(win)
  local id, f = win:id(), win:frame()
  local placed = placedFrame[id]
  if not originalFrame[id] or not (placed and near(f, placed)) then
    originalFrame[id] = copyFrame(f)
  end
end

-- 配置を変えた直後に呼ぶ。本設定が置いた位置を覚える（手で動かしたかの判定に使う）
local function placedBy(win)
  placedFrame[win:id()] = copyFrame(win:frame())
end

local function setFrameRemembered(win, frame)
  remember(win)
  win:setFrame(frame, 0)  -- 0 = アニメーションなし（即応させる）
  placedBy(win)
end

-- 最大化（パッド 46 / ⌥=）
local function maximize()
  local win = hs.window.focusedWindow()
  if win then setFrameRemembered(win, workArea(win:screen())) end
end

-- 左右に配置（パッド 44 / 45、⌥9 / ⌥0）。同じ向きで続けて押すと幅が 1/2 → 2/3 → 1/3 と変わる。
local SNAP_RATIOS = { 1 / 2, 2 / 3, 1 / 3 }

local function snapFrame(a, side, r)
  if side == "left" then return { x = a.x, y = a.y, w = a.w * r, h = a.h } end
  return { x = a.x + a.w * (1 - r), y = a.y, w = a.w * r, h = a.h }  -- right
end

local function snap(side)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local a = workArea(win:screen())
    local cur = win:frame()
    local nextIdx = 1
    for i, r in ipairs(SNAP_RATIOS) do
      if near(cur, snapFrame(a, side, r)) then nextIdx = i % #SNAP_RATIOS + 1 break end
    end
    setFrameRemembered(win, snapFrame(a, side, SNAP_RATIOS[nextIdx]))
  end
end

-- 本設定で動かす前の位置と大きさに戻す（⌥-）
local function restore()
  local win = hs.window.focusedWindow()
  if not win then return end
  local id = win:id()
  local original = originalFrame[id]
  if not original or near(win:frame(), original) then
    -- 何も起きないと効いていないように見えるので、戻す位置がないことを知らせる
    hs.alert.show("No undo history", 1)
    originalFrame[id] = nil
    return
  end
  win:setFrame(original, 0)
  originalFrame[id] = nil
  placedFrame[id] = nil
end

-- グリッドを表示し、フォーカス中のウィンドウを手で配置する（⌥G）。
-- マス目の文字キーを2つ押すと、その2マスを対角とする範囲に配置される。Esc で閉じる。
local function showGrid()
  local win = hs.window.focusedWindow()
  if not win then return end
  remember(win)
  hs.grid.show(function()
    if hs.window.get(win:id()) then placedBy(win) end
  end)
end

-- 最小化（⌥M）。しまった直後にもう一度押すと、しまったウィンドウを元に戻す。
-- しまうと macOS が別のウィンドウへフォーカスを移すので、そのフォーカス先を覚えておき、
-- フォーカスがそこから動いていなければ「直後」とみなす。別のウィンドウを選んでから押すと、
-- そのウィンドウをしまう。
local FOCUS_SETTLE = 0.5
local minimizeState = {}  -- win: しまったウィンドウ / focusAfter: その後のフォーカス先 / timer

local function focusedId()
  local win = hs.window.focusedWindow()
  return win and win:id() or false
end

local function toggleMinimize()
  local last = minimizeState.win
  if last and last:isMinimized()
    and (minimizeState.focusAfter == nil or minimizeState.focusAfter == focusedId()) then
    last:unminimize()
    last:focus()
    minimizeState.win = nil
    return
  end

  local win = hs.window.focusedWindow()
  if not win then return end
  win:minimize()
  minimizeState.win = win
  minimizeState.focusAfter = nil  -- フォーカスが移り終わるまでは「直後」とみなす
  if minimizeState.timer then minimizeState.timer:stop() end
  -- タイマーは表に保持する（ローカル変数だけだと GC で止まる）
  minimizeState.timer = hs.timer.doAfter(FOCUS_SETTLE, function()
    minimizeState.focusAfter = focusedId()
  end)
end

-- フォーカス中のウィンドウを、大きさを変えずに次のモニターへ移す。
-- 2台なら押すたびに行き来、3台以上なら順番に回る。マウスカーソルは動かさない。
local function moveToNextScreen()
  local win = hs.window.focusedWindow()
  if not win then return end
  local screen = win:screen()
  local target = screen and screen:next()
  if not target or target:id() == screen:id() then
    print("[pad] screen: 移動先のモニターがない（1台のみ）")
    return
  end
  -- noResize: 大きさはそのまま（画面内の相対位置は保つ）。
  -- ensureInScreen: 移動先のモニターの方が小さいときは、はみ出さないよう収める。
  win:moveToScreen(target, true, true, 0)
  print(string.format("[pad] screen: %s → %s", screen:name() or "?", target:name() or "?"))
end

-- ---------------------------------------------------------------------
-- プレゼン / 画面操作
-- ---------------------------------------------------------------------

-- PowerPoint のスライドを前後に送る。
-- キーは PowerPoint 宛てに送るので、他のアプリを前面にしていても効く。
-- 矢印キーではなく PageUp/PageDown を使う: 矢印だと編集画面でテキスト選択中に
-- カーソル移動になってしまうが、PageUp/PageDown は編集画面でもスライドショー中でもページが変わる。
-- AppleScript 方式はオートメーション権限が別途必要になるので使わない。
local function slide(key)
  return function()
    local app = runningApp(APPS.powerpoint)
    if not app then
      print("[pad] slide: PowerPoint が起動していない")
      return
    end
    local front = hs.application.frontmostApplication()
    if front and front:pid() == app:pid() then
      hs.eventtap.keyStroke({}, key, 0)       -- 前面なら通常送出（最も確実）
    else
      hs.eventtap.keyStroke({}, key, 0, app)  -- 背面なら PowerPoint のプロセスへ直接送る
    end
  end
end

local prevSlide = slide("pageup")
local nextSlide = slide("pagedown")

-- 通知センターを開く。AppleScript方式はオートメーション権限や項目名で弾かれやすいので、
-- メニューバー右端（時計）を直接クリックする。必要権限はアクセシビリティのみ。
-- 複数モニター対応: 主モニター固定ではなく「今カーソルがいるモニター」の時計を押す。
-- クリック後はマウス位置を元に戻すので、操作の邪魔にならない。
local function openNotificationCenter()
  local screen = hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
  local f = screen:fullFrame()
  local target = hs.geometry.point(f.x + f.w - 6, f.y + 11) -- そのモニター右上の時計あたり
  local orig = hs.mouse.absolutePosition()
  hs.eventtap.leftClick(target)
  hs.mouse.absolutePosition(orig)
  print(string.format("[notif] clicked menubar clock at %d,%d on %s",
    target.x, target.y, screen:name() or "?"))
end

-- ---------------------------------------------------------------------
-- パッド割り当て
-- ---------------------------------------------------------------------
-- 実機の並びは MPC/ドラム式（36が左下、行ごとに上へ）:
--
--   上段  [48 スライド←]     [49 スライド→]     [50 別モニターへ移動] [51 通知センター]   ← プレゼン/画面
--   3段目 [44 左に配置]      [45 右に配置]      [46 最大化]           [47 モニター内巡回] ← ウィンドウ操作
--   2段目 [40 Slack]         [41 ブラウザ]      [42 Claude]           [43 メモ]           ← 連絡/情報
--   下段  [36 VSCode]        [37 PyCharm]       [38 Excel]            [39 Sourcetree]     ← 開発
--
-- 手前（下段）ほど使用頻度の高い開発系、奥（上段）ほど画面全体に効く操作。
local PAD_ACTION = {
  -- 下段: 開発
  [36] = focus(APPS.vscode),
  [37] = focus(APPS.pycharm),
  [38] = focus(APPS.excel),
  [39] = focus(APPS.sourcetree),
  -- 2段目: 連絡 / 情報
  [40] = focus(APPS.slack),
  [41] = focus(APPS.browser),
  [42] = focus(APPS.claude),
  [43] = focus(APPS.notes),
  -- 3段目: ウィンドウ操作
  [44] = snap("left"),
  [45] = snap("right"),
  [46] = maximize,
  [47] = cycleFrontmostOnScreen,
  -- 上段: プレゼン / 画面
  [48] = prevSlide,
  [49] = nextSlide,
  [50] = moveToNextScreen,
  [51] = openNotificationCenter,
}

-- ---------------------------------------------------------------------
-- キーボードショートカット（⌥9 / 0 / = / - / G / M）
-- ---------------------------------------------------------------------
-- パッドが無くても使えるよう、ウィンドウ操作をキーにも割り当てる。
-- ⌥ で入力される特殊文字（ª º ≠ – © µ）は入力できなくなる。
-- 有効なホットキーは hs.hotkey 自身が保持するので、ここで参照を持たなくても回収されない。
local function bindKey(key, fn)
  hs.hotkey.bind(MOD, key, fn)
end

bindKey(WINDOW_KEYS.left,     snap("left"))
bindKey(WINDOW_KEYS.right,    snap("right"))
bindKey(WINDOW_KEYS.maximize, maximize)
bindKey(WINDOW_KEYS.restore,  restore)
bindKey(WINDOW_KEYS.grid,     showGrid)
bindKey(WINDOW_KEYS.minimize, toggleMinimize)

hs.grid.setGrid(GRID_SIZE)
hs.grid.setMargins("0x0")
-- ⌥G の配置は hs.grid が既定のアニメーション付きで動かすので、他の操作と同じく即座に動くよう 0 にする。
hs.window.animationDuration = 0

-- ---------------------------------------------------------------------
-- Office の編集キー（⌥Return → F2）
-- ---------------------------------------------------------------------
-- Mac の F2 は fn と一緒に押さないと効かず押しにくいので、⌥Return で F2 を送る。
-- ⌥Return を他のアプリから奪わないよう、Office のウィンドウにフォーカスがある間だけキーを有効にする。
local OFFICE_APPS = { APPS.word, APPS.excel, APPS.powerpoint }

local officeNames, officeBundleIDs = {}, {}
for _, spec in ipairs(OFFICE_APPS) do
  officeNames[#officeNames + 1] = spec.name
  for _, id in ipairs(spec.bundleIDs) do officeBundleIDs[id] = true end
end

local function officeIsFront()
  local front = hs.application.frontmostApplication()
  return front ~= nil and officeBundleIDs[front:bundleID() or ""] == true
end

local officeEditHotkey
officeEditHotkey = hs.hotkey.new(MOD, OFFICE_EDIT_KEY, function()
  if officeIsFront() then
    hs.eventtap.keyStroke({}, "f2", 0)
  else
    officeEditHotkey:disable()  -- 切り替えの通知が遅れて有効のまま残っていた場合の保険
  end
end)

-- 前面のアプリが Office のときだけ有効にする。
-- ウィンドウを切り替えると「前のウィンドウから外れた」「次のウィンドウに入った」の順番が
-- 前後することがあるので、どちらの通知でも前面のアプリを見て決め直す。
local function syncOfficeEditKey()
  if officeIsFront() then
    officeEditHotkey:enable()
  else
    officeEditHotkey:disable()
  end
end

-- 購読しているウィンドウフィルタは hs.window.filter 自身が保持するので、回収されない。
local officeFilter = hs.window.filter.new(officeNames)
officeFilter:subscribe({ hs.window.filter.windowFocused, hs.window.filter.windowUnfocused },
  syncOfficeEditKey)
syncOfficeEditKey()  -- 読み込んだ時点で Office が前面なら、すぐ使えるようにする

-- ---------------------------------------------------------------------
-- MIDI 接続（起動時 + 抜き差しに追従）
-- ---------------------------------------------------------------------
local function handleMidi(deviceName, commandType, metadata)
  if DEBUG then
    print(string.format("[MIDI] dev=%s type=%s meta=%s",
      tostring(deviceName), tostring(commandType), hs.inspect(metadata)))
  end

  if commandType ~= "noteOn" then return end

  -- 押した瞬間（velocity>0）だけ反応させる。
  -- パッドによっては velocity 0 の noteOn を「離した」代わりに送るため、その分は捨てる。
  if (metadata.velocity or 0) > 0 then
    local action = PAD_ACTION[metadata.note]
    if action then action() end
  end
end

local connected = {}  -- デバイス名 → hs.midi オブジェクト

local function syncDevices()
  local present = {}
  for _, name in ipairs(hs.midi.devices()) do
    present[name] = true
    -- 対象デバイスだけを開く。"ネットワーク" や "Bluetooth" などの仮想ポートを開くと
    -- "No MIDI Device End Points detected" エラーが出るため、名前で絞り込む。
    if name:find(DEVICE_MATCH, 1, true) and not connected[name] then
      local dev = hs.midi.new(name)
      if dev then
        dev:callback(function(_, deviceName, commandType, _, metadata)
          handleMidi(deviceName, commandType, metadata)
        end)
        connected[name] = dev
        print("[MIDI] connected: " .. name)
      end
    end
  end

  -- 抜かれたデバイスを片付ける
  for name, dev in pairs(connected) do
    if not present[name] then
      dev:callback(nil)
      connected[name] = nil
      print("[MIDI] disconnected: " .. name)
    end
  end

  local names = {}
  for name in pairs(connected) do table.insert(names, name) end
  table.sort(names)
  if #names == 0 then
    print("[MIDI] " .. DEVICE_MATCH .. " が見つからない。接続中のMIDI: "
      .. hs.inspect(hs.midi.devices()))
  end
  return names
end

local activeDevices = syncDevices()

-- USB抜き差しに追従して再接続
hs.midi.deviceCallback(function(devices)
  if DEBUG then print("[MIDI] devices changed: " .. hs.inspect(devices)) end
  syncDevices()
end)

hs.alert.show(#activeDevices > 0
  and ("SMC-PAD config loaded: " .. table.concat(activeDevices, ", "))
  or  "SMC-PAD config loaded (デバイス未接続)")
