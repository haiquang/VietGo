cask "vietgo" do
  version "1.0.4"
  sha256 "a540927221da9055a5668f27488e1c9f060ff0a7767bf4c510bd8765dfbaea6d"

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
