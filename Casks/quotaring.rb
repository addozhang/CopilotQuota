cask "quotaring" do
  version "2.0.1"
  sha256 "ba5ba96f0cba1f82a932d347b50c8fdca4f52df76ed1ea4a776ed147b064ea28"

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
