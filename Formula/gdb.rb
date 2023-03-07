class Gdb < Formula
  desc "GNU debugger"
  homepage "https://www.gnu.org/software/gdb/"
  url "https://ftp.gnu.org/gnu/gdb/gdb-13.1.tar.xz"
  mirror "https://ftpmirror.gnu.org/gdb/gdb-13.1.tar.xz"
  sha256 "115ad5c18d69a6be2ab15882d365dda2a2211c14f480b3502c6eba576e2e95a0"
  license "GPL-3.0-or-later"
  revision 1
  head "https://sourceware.org/git/binutils-gdb.git"

  depends_on "python@3.11"
  depends_on "texinfo" => :build
  depends_on "xz" # required for lzma support
  head do
    depends_on "gmp"
  end

  uses_from_macos "expat"
  uses_from_macos "ncurses"

  on_linux do
    depends_on "pkg-config" => :build
    depends_on "guile"
  end

  conflicts_with "i386-elf-gdb", because: "both install include/gdb, share/gdb and share/info"
  conflicts_with "x86_64-elf-gdb", because: "both install include/gdb, share/gdb and share/info"

  fails_with :clang do
    build 800
    cause <<~EOS
      probe.c:63:28: error: default initialization of an object of const type
      'const any_static_probe_ops' without a user-provided default constructor
    EOS
  end

  patch :DATA

  def install
    args = %W[
      --enable-targets=all
      --prefix=#{prefix}
      --disable-debug
      --disable-dependency-tracking
      --with-lzma
      --with-python=#{Formula["python@3.11"].opt_bin}/python3
      --disable-binutils
    ]

    if build.head? then
      args += %W[
      --with-libgmp-prefix=#{Formula["gmp"].opt_prefix}
      --with-liblzma-prefix=#{Formula["xz"].opt_prefix}
      ]
    end

    mkdir "build" do
      system "../configure", *args
      system "make"

      # Don't install bfd or opcodes, as they are provided by binutils
      system "make", "install-gdb", "maybe-install-gdbserver"
    end
  end

  def caveats
    <<~EOS
      gdb requires special privileges to access Mach ports.
      You will need to codesign the binary. For instructions, see:

        https://sourceware.org/gdb/wiki/BuildingOnDarwin
    EOS
  end

  test do
    system bin/"gdb", bin/"gdb", "-configuration"
  end
end

__END__
# https://sourceware.org/bugzilla/show_bug.cgi?id=25560#c1
diff --git a/gdb/exec.c b/gdb/exec.c
index 68b35204068..c312b71f475 100644
--- a/gdb/exec.c
+++ b/gdb/exec.c
@@ -552,8 +552,8 @@ file_command (const char *arg, int from_tty)
 {
   /* FIXME, if we lose on reading the symbol file, we should revert
      the exec file, but that's rough.  */
-  exec_file_command (arg, from_tty);
   symbol_file_command (arg, from_tty);
+  exec_file_command (arg, from_tty);
   if (deprecated_file_changed_hook)
     deprecated_file_changed_hook (arg);
 }
