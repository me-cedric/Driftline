class Driftline < Formula
  desc "Native macOS file transfer client with secure SFTP-first architecture"
  homepage "https://github.com/OWNER/Driftline"
  url "https://github.com/OWNER/Driftline/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "TODO"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--product", "driftline"
    bin.install ".build/release/driftline"
  end

  test do
    assert_match "0.1.0", shell_output("#{bin}/driftline --version")
  end
end
