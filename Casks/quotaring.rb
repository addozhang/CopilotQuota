cask "quotaring" do
  version "2.0.0"
  sha256 "41c1f23a5ce59c253fa58a79de35bc2ba299aa8c9e80c4efc9600118602947d8"

  url "https://github.com/addozhang/QuotaRing/releases/download/v#{version}/QuotaRing-#{version}.dmg"
  name "QuotaRing"
  desc "Battery-style macOS menu bar app and desktop widgets for your AI quotas"
  homepage "https://github.com/addozhang/QuotaRing"

  depends_on macos: ">= :sonoma"

  app "QuotaRing.app"

  zap trash: [
    "~/Library/Preferences/app.solocraft.quotaring.plist",
    "~/Library/Preferences/app.solocraft.copilotquota.plist",
  ]
end
