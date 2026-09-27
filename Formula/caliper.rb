class Caliper < Formula
  desc "Menu bar tool for measuring distances on screen"
  homepage "https://github.com/FaizanAshiq/caliper"
  url "https://github.com/FaizanAshiq/caliper/archive/refs/tags/v0.1.5.tar.gz"
  sha256 "60584f3ac98ff3a3b260dfc156e8b36d40c33bf9c95284323e2154ef2b36cf0a"
  license "MIT"
  depends_on macos: :sonoma

  def install
    system "./build.sh", "release"
    prefix.install "dist/Caliper.app"
    prefix.install "scripts"
  end

  def caveats
    <<~EOS
      Caliper was built on this machine, so it launches without a Gatekeeper prompt.

      Open it with:
        open #{prefix}/Caliper.app

      Homebrew builds in a sandbox that cannot reach your keychain, so this copy
      is signed ad hoc and macOS forgets Screen Recording on every upgrade. Two
      commands fix that for good:
        #{prefix}/scripts/signing-identity.sh
        codesign --force --sign "Caliper Local Signing" #{prefix}/Caliper.app

      The ruler, marquee and guides need no permissions. The loupe, eyedropper
      and edge snapping need Screen Recording, which Caliper asks for only when
      you first use one of them.
    EOS
  end

  test do
    app = prefix/"Caliper.app"
    assert_predicate app/"Contents/MacOS/Caliper", :executable?
    assert_equal "com.faizanashiq.caliper",
                 shell_output("/usr/bin/plutil -extract CFBundleIdentifier raw '#{app}/Contents/Info.plist'").strip
  end
end
