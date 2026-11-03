# Homebrew cask for Gingerbrew.
#
# Copy this to Casks/gingerbrew.rb in a tap repository (github.com/luanpanno/homebrew-tap)
# and update `version` and `sha256` for each release (the release notes include the SHA-256).
# Users then install with:
#
#   brew install --cask luanpanno/tap/gingerbrew
#
cask "gingerbrew" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/luanpanno/gingerbrew/releases/download/v#{version}/Gingerbrew-#{version}.dmg"
  name "Gingerbrew"
  desc "Minimal menu bar app for managing Homebrew packages"
  homepage "https://github.com/luanpanno/gingerbrew"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Gingerbrew.app"

  # Until releases are notarized, remove the quarantine flag so Gatekeeper allows it.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Gingerbrew.app"]
  end

  uninstall quit: "com.luanpanno.gingerbrew"

  zap trash: [
    "~/Library/Caches/com.luanpanno.gingerbrew",
    "~/Library/Preferences/com.luanpanno.gingerbrew.plist",
  ]
end
