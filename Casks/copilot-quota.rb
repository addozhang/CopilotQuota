# Legacy v1.x Cask — superseded by `Casks/quotaring.rb` in v2.0+.
cask "copilot-quota" do
  version "1.4.0"
  sha256 "94e0f058c4827614d9a262f72947a450a42a3ab904657d95d5b698d7a7f01b79"

  url "https://github.com/addozhang/CopilotQuota/releases/download/v#{version}/CopilotQuota-#{version}.dmg"
  name "Copilot Quota"
  desc "Menu bar app and battery-style macOS widget for your GitHub Copilot quota"
  homepage "https://github.com/addozhang/CopilotQuota"

  depends_on macos: ">= :sonoma"

  app "Copilot Quota.app"

  zap trash: [
    "~/Library/Preferences/app.solocraft.copilotquota.plist",
    "~/Library/Preferences/com.addo.copilotquota.plist",
  ]
end
