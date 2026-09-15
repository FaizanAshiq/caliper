class Caliper < Formula
  desc "Menu bar tool for measuring distances on screen"
  homepage "https://github.com/FaizanAshiq/caliper"
  url "https://github.com/FaizanAshiq/caliper/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_THE_TARBALL_SHA256"
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

      Run this once so upgrades keep the permission you grant:
        #{prefix}/scripts/signing-identity.sh

      The ruler, marquee and guides need no permissions. The loupe, eyedropper
      and edge snapping need Screen Recording, which Caliper asks for only when
      you first use one of them.
    EOS
  end
end
