# roamion-agent Homebrew Formula の【テンプレ】
# 配布対象: linux-x64 / darwin-arm64 の 2 platform（Intel Mac は D11 で対象外、Windows は Scoop で後続）
#
# ここはテンプレであり、配布に使われる実体ではない。tag(v*) push 時に
# `.github/workflows/release.yml` の publish ジョブがこのファイルをコピーし、
#   - version を tag から
#   - REPLACE_WITH_SHA256_* を各 tarball の実 sha256 から
# 置換して tap リポジトリ（tom-shimoda/homebrew-tap）の Formula/roamion-agent.rb へ push する。
# → **sha256 と version を手で書き換えないこと**（次のリリースで CI に上書きされる）。
#   利用者側:  brew tap tom-shimoda/tap && brew install roamion-agent
#
# url は **public 配布リポ tom-shimoda/roamion-agent** の Release アセットを指す（D9）。
# ソースリポ(roamion)は private のままで、private リポの Release は匿名 DL 不可＝brew から取れないため。
#
# ローカル検証（tap 不要 / sha256 を実値にした複製で行う）:
#   brew install --build-from-source ./roamion-agent.rb
#   ruby -c ./roamion-agent.rb            # 構文チェック
#
# Windows(win32-x64) は receive.js の .exe/HOME 対応・常駐テンプレ完了後に別途対応。

class RoamionAgent < Formula
  desc "Dial-out agent bridging Claude Agent SDK sessions to roamion central"
  homepage "https://roamion.tomolabo.jp"
  version "0.1.3"
  license "ISC"

  on_macos do
    # Intel Mac(darwin-x64) は配布対象外（D11）。GitHub Actions の x86_64 macOS イメージが
    # 2027-08 で終了する一方 macOS runner は課金分数を 10 倍消費するため、ビルドを畳んだ。
    # depends_on を書かずに url を未定義のままにすると "no available formula" 系の
    # 分かりにくいエラーになるので、arch 要件として明示して失敗させる。
    depends_on arch: :arm64
    url "https://github.com/tom-shimoda/roamion-agent/releases/download/v#{version}/roamion-agent-#{version}-darwin-arm64.tar.gz"
    sha256 "1f6cda285363d9b74b978ba14110a4ceba144c3d731709ece8f916e020db8a14"
  end

  on_linux do
    # linux-arm64 は将来対応（CI マトリクスに arm64 runner 追加後）。それまでは明示的に弾く。
    depends_on arch: :x86_64
    url "https://github.com/tom-shimoda/roamion-agent/releases/download/v#{version}/roamion-agent-#{version}-linux-x64.tar.gz"
    sha256 "ce75553fe9a6d12da48d39dcc66b2d8d30a22f734679e481f3ea7f689491a4a7"
  end

  def install
    # 【重要】native claude を bin に置かないこと。
    #   本物の Claude Code CLI (`claude`) と PATH 上で名前衝突するため、両者は libexec へ隔離する。
    #   roamion-agent は同梱 claude を「env ROAMION_CLI_PATH → dirname(execPath)/claude」の順で解決する。
    #   bin には env script を置き ROAMION_CLI_PATH を明示注入する（symlink 経由の dirname(execPath)
    #   解決は macOS で realpath されない可能性があるため、明示指定のほうが確実）。
    #
    # 【ROAMION_SERVICE_EXEC を渡す理由】
    #   `roamion-agent service install` は systemd unit / launchd plist の ExecStart を作る。
    #   何も渡さないと process.execPath = Cellar のバージョン込み実体パス
    #   (…/Cellar/roamion-agent/<version>/libexec/roamion-agent) になり、`brew upgrade` で
    #   旧 Cellar が消えた瞬間に常駐が起動不能になる。
    #   opt_bin は /opt/homebrew/opt/roamion-agent/bin（常に現行版を指す symlink）なので、
    #   これを ExecStart に使えば upgrade 後も unit の作り直しは不要。
    #   さらに opt_bin/"roamion-agent" は下の write_env_script が生成したラッパー自身なので、
    #   daemon 起動時にも ROAMION_CLI_PATH が注入される（= 隣接 claude の解決も同時に担保）。
    #   ExecStart に libexec の実体を直に指定すると env が無く claude 解決が壊れるため、
    #   必ず「opt_bin のラッパー」を渡すこと。
    libexec.install "roamion-agent", "claude"
    (bin/"roamion-agent").write_env_script libexec/"roamion-agent",
                                           ROAMION_CLI_PATH:     libexec/"claude",
                                           ROAMION_SERVICE_EXEC: opt_bin/"roamion-agent"
  end

  # 注意: brew services（service ブロック）は現状あえて用意していない。
  #   roamion-agent は CENTRAL_URL/AGENT_TOKEN を process.env からのみ読み、agent.env を
  #   自前で読むフォールバックが無い。brew services が生成する launchd には env が無いため
  #   keep_alive 下で毎回 fatal→再起動ループになる。
  #   → 常駐は roamion-agent 内蔵の `roamion-agent service install` を使う。
  #     （agent.env を systemd の EnvironmentFile / launchd の source として明示注入する。）

  def caveats
    <<~EOS
      この Formula はバイナリを配置するだけです（常駐はしません）。常駐は同梱の
      `roamion-agent service install` で登録してください。

      1) トークンを取得する:
           https://roamion.tomolabo.jp にログイン → agent を新規作成。
           平文トークンは【作成時に一度だけ】表示されます（後から再表示できません）。

      2) 常駐登録（Linux=systemd user unit / macOS=LaunchAgent）:
           roamion-agent service install --url wss://roamion.tomolabo.jp --token <トークン>

         【推奨】--token はコマンドライン引数なので ps / /proc から同一ホストの他ユーザーに
         見えます。共有ホストでは --token-stdin か環境変数 AGENT_TOKEN を使ってください:
           printf '%s' "$AGENT_TOKEN" | \\
             roamion-agent service install --url wss://roamion.tomolabo.jp --token-stdin

         既に agent.env を用意済みなら:
           roamion-agent service install --env /path/to/agent.env

         トークンは ~/.config/roamion-agent/agent.env に chmod 600 で保存され、
         unit/plist には直書きされません。

      3) Claude 認証（ユーザー持ち。どちらか一方）:
           - ~/.claude のサブスク認証（`claude` に一度ログイン済みであること）
           - 環境変数 ANTHROPIC_API_KEY（agent.env に追記可）
         常駐はログインユーザー権限で動くため、~/.claude がそのまま使えます。

      4) 状態確認 / 解除:
           roamion-agent service status
           roamion-agent service uninstall           # 常駐解除（agent.env は残す）
           roamion-agent service uninstall --purge   # agent.env も削除

         brew upgrade 後の再登録は不要です。常駐の起動パスにはバージョンに依存しない
         #{opt_bin}/roamion-agent を使うため、upgrade しても壊れません。

      macOS で Gatekeeper に警告された場合（notarization は将来対応）:
        xattr -dr com.apple.quarantine #{opt_libexec}/roamion-agent
        xattr -dr com.apple.quarantine #{opt_libexec}/claude
    EOS
  end

  test do
    # CENTRAL_URL 無しでは起動時に fatal 終了する（②経路の健全性確認）。
    assert_match(/CENTRAL_URL/i, shell_output("#{bin}/roamion-agent 2>&1", 1))
    # service サブコマンドは env 無しでも動く（CENTRAL_URL fatal より前に dispatch される）。
    # 注意: `service status` の exit code は常駐の有無で 0/1 が変わるため exit code に依存しない
    #       （既に常駐登録済みの環境で `brew test` が落ちないようにする）。
    assert_match "roamion-agent service", shell_output("#{bin}/roamion-agent service --help 2>&1")
  end
end
