class Driftline < Formula
  desc "Native macOS file transfer client with secure SFTP-first architecture"
  homepage "https://github.com/me-cedric/Driftline"
  url "https://github.com/me-cedric/Driftline/archive/refs/tags/v0.2.0.tar.gz"
  sha256 ""
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--product", "driftline"
    bin.install ".build/release/driftline"
  end

  test do
    assert_match "0.2.0", shell_output("#{bin}/driftline --version")
  end
end
