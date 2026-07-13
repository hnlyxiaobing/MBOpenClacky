# MBOpenClacky Homebrew formula (tap).
#
# Install:
#   brew tap hnlyxiaobing/mbopenclacky
#   brew install mbopenclacky
#
# Or without a tap:
#   brew install --formula ./deploy/homebrew/Formula/mbopenclacky.rb
#
# NOTE: Replace each REPLACE_WITH_RELEASE_SHA256 with the real sha256
# (run `brew fetch --build-from-source` or `shasum -a 256 <tarball>` per
# release). After publishing a GitHub Release, bump `version` and the
# per-arch sha256 values so `brew upgrade` works.

class Mbopenclacky < Formula
  desc "MoonBit rewrite of the openclacky AI Agent CLI"
  homepage "https://github.com/hnlyxiaobing/MBOpenClacky"
  version "0.1.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/hnlyxiaobing/MBOpenClacky/releases/download/v#{version}/mbopenclacky-darwin-arm64.tar.gz"
      sha256 "REPLACE_WITH_RELEASE_SHA256"
    end
    on_intel do
      url "https://github.com/hnlyxiaobing/MBOpenClacky/releases/download/v#{version}/mbopenclacky-darwin-amd64.tar.gz"
      sha256 "REPLACE_WITH_RELEASE_SHA256"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/hnlyxiaobing/MBOpenClacky/releases/download/v#{version}/mbopenclacky-linux-arm64.tar.gz"
      sha256 "REPLACE_WITH_RELEASE_SHA256"
    end
    on_intel do
      url "https://github.com/hnlyxiaobing/MBOpenClacky/releases/download/v#{version}/mbopenclacky-linux-amd64.tar.gz"
      sha256 "REPLACE_WITH_RELEASE_SHA256"
    end
  end

  # Native build links libcurl (HTTP client) and libssl/libcrypto (crypto).
  # Homebrew provides both transitively; no explicit dependency needed for
  # the prebuilt binary.
  def install
    bin.install "mbopenclacky"
  end

  test do
    assert_match "MBOpenClacky", shell_output("#{bin}/mbopenclacky --version 2>&1")
  end
end
