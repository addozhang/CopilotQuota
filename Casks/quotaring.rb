cask "quotaring" do
  version "2.1.0"
  sha256 "3ae5b602b5fd3bd3bd905a87dc68ee1213a4dd281b7863e80d3ff7bd4373b982"

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
