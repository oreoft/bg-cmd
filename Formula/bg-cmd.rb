# Homebrew Formula for bgs (bg-cmd)
# bgs = bilibili goods
# A CLI tool for batch publishing and buying items on Bilibili Mall

class BgCmd < Formula
  desc "Bilibili Goods CLI - batch publish/buy items on Bilibili Mall"
  homepage "https://github.com/oreoft/bg-cmd"
  url "https://github.com/oreoft/bg-cmd/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"  # Update when releasing
  license "MIT"
  version "1.0.0"

  depends_on "jq"
  depends_on "qrencode" => :recommended
  # openssl and curl are built-in on macOS

  def install
    # Install main command
    bin.install "bin/bgs"

    # Install subcommands and libraries
    libexec.install Dir["libexec/*"]

    # Update libexec path reference in main script
    inreplace bin/"bgs", 
      'LIBEXEC_DIR="${SCRIPT_DIR}/../libexec"',
      "LIBEXEC_DIR=\"#{libexec}\""
  end

  def caveats
    <<~EOS
      bgs (bilibili goods) has been installed!

      Quick start:
        1. Login with QR code:
           $ bgs auth login

        2. Set your publish price:
           $ bgs config publish.price 200        # Fixed: 200 yuan
           $ bgs config publish.price [100,300]  # Random: 100-300 yuan

        3. Publish items from inventory:
           $ bgs publish

        4. Buy items:
           $ bgs buy [item_id1,item_id2,...]

      For more help:
        $ bgs help
        $ bgs <command> --help

      Configuration is stored in: ~/.bg-cmd/
    EOS
  end

  test do
    assert_match "bgs version", shell_output("#{bin}/bgs version")
  end
end
