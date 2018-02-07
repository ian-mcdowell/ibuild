class ibuild < Formula
  desc "Build multi-architecture iOS libraries from build systems like CMake, Make, and Xcode."
  homepage "https://github.com/IMcD23/ibuild"
  url "https://github.com/IMcD23/ibuild/archive/1.0.0.zip"
  sha256 ""
  head "https://github.com/IMcD23/ibuild.git"

  depends_on :xcode
  depends_on "cmake"
  depends_on "automake"
  depends_on "autoconf"

  def install
    system "make", "install", "PREFIX=${prefix}"
  end
end