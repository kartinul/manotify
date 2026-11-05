# Copy to Formula/manotify.rb in github.com/kartinul/homebrew-tap.
# shortcut: HEAD only until there is a tagged release; then add url + sha256.
class Manotify < Formula
  desc "Send native macOS notifications from the command line"
  homepage "https://github.com/kartinul/manotify"
  license "MIT"
  head "https://github.com/kartinul/manotify.git", branch: "main"

  depends_on macos: :ventura

  def install
    system "scripts/bundle.sh", prefix
    bin.write_exec_script prefix/"manotify.app/Contents/MacOS/manotify"
  end

  test do
    system "codesign", "--verify", prefix/"manotify.app"
    assert_match "nothing to send", shell_output("#{bin}/manotify --dry-run 2>&1", 64)
  end
end
