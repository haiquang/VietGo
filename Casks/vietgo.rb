cask "vietgo" do
  version "1.0.3"
  sha256 "7397ca223b7d187d64656971bb4e2b03c738c9f0c8917f9bbed9009cc34f062e"

  url "https://github.com/haiquang/VietGo/releases/download/v#{version}/VietGo-v#{version}-macos-arm64.dmg"
  name "VietGo"
  desc "Native macOS Vietnamese input engine supporting Telex and VNI"
  homepage "https://github.com/haiquang/VietGo"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "VietGo.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-rd", "com.apple.quarantine", "{{appdir}}/VietGo.app"],
        must_succeed: false
  end

  uninstall quit: "org.vietgo.VietGo"

  zap trash: [
    "~/Library/Preferences/org.vietgo.VietGo.plist",
  ]

  caveats <<~EOS
    Sau khi mở VietGo lần đầu, hãy cấp quyền Trợ năng (Accessibility) tại:
      System Settings → Privacy & Security → Accessibility → bật VietGo
  EOS
end
