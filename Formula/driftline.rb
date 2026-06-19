class Driftline < Formula
  desc "Native macOS file transfer client with secure SFTP-first architecture"
  homepage "https://github.com/me-cedric/Driftline"
  url "https://github.com/me-cedric/Driftline/archive/refs/tags/v0.6.0.tar.gz"
  sha256 "e6011b4648252d84c2ace2c2831bfd23b148f60128604c93bce434a0c870a33c"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--product", "driftline"
    bin.install ".build/release/driftline"
  end

  test do
    assert_match "0.6.0", shell_output("#{bin}/driftline --version")
  end
end
