class Gdb < Formula
  desc "GNU debugger"
  homepage "https://www.gnu.org/software/gdb/"
  url "https://ftp.gnu.org/gnu/gdb/gdb-10.1.tar.xz"
  mirror "https://ftpmirror.gnu.org/gdb/gdb-10.1.tar.xz"
  sha256 "f82f1eceeec14a3afa2de8d9b0d3c91d5a3820e23e0a01bbb70ef9f0276b62c0"
  license "GPL-3.0-or-later"
  revision 1
  head "https://sourceware.org/git/binutils-gdb.git"

  depends_on "python@3.9"
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

  patch :DATA   # Common (stable + head) patches at bottom of this file

  stable do
    patch <<BUG_26861
diff -U3 gdb-10.1-ORIG/gdb/target.c gdb-10.1/gdb/target.c
--- gdb-10.1-ORIG/gdb/target.c	2020-10-24 06:23:02.000000000 +0200
+++ gdb-10.1/gdb/target.c	2021-04-07 20:18:56.000000000 +0200
@@ -2146,7 +2146,7 @@
 void
 target_mourn_inferior (ptid_t ptid)
 {
-  gdb_assert (ptid == inferior_ptid);
+  gdb_assert (ptid.pid () == inferior_ptid.pid ());
   current_top_target ()->mourn_inferior ();

   /* We no longer need to keep handles on any of the object files.
BUG_26861
  end

  head do
    ## The need for this might go away any minute (and then this patch
    ## will probably fail to apply). If that happens, just remove this
    ## whole `head do` ... `end` section
    patch <<WUNUSED_STATUS
diff --git a/gdb/darwin-nat.c b/gdb/darwin-nat.c
index 587f5317416..a6790792fb6 100644
--- a/gdb/darwin-nat.c
+++ b/gdb/darwin-nat.c
@@ -903,8 +903,6 @@ darwin_suspend_inferior_threads (struct inferior *inf)
 void
 darwin_nat_target::resume (ptid_t ptid, int step, enum gdb_signal signal)
 {
-  struct target_waitstatus status;
-
   int nsignal;

   inferior_debug
WUNUSED_STATUS
  end

  def install
    args = %W[
      --enable-targets=all
      --prefix=#{prefix}
      --disable-debug
      --disable-dependency-tracking
      --with-lzma
      --with-python=#{Formula["python@3.9"].opt_bin}/python3
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
# https://sourceware.org/bugzilla/show_bug.cgi?id=24069#c11
diff -U3 gdb-10.1-ORIG/gdb/darwin-nat.c gdb-10.1/gdb/darwin-nat.c
--- gdb-10.1-ORIG/gdb/darwin-nat.c	2020-10-24 06:23:02.000000000 +0200
+++ gdb-10.1/gdb/darwin-nat.c	2021-04-07 20:17:15.000000000 +0200
@@ -1108,9 +1108,6 @@
 	      inferior_debug (4, _("darwin_wait: pid=%d exit, status=0x%x\n"),
 			      res_pid, wstatus);

-	      /* Looks necessary on Leopard and harmless...  */
-	      wait4 (inf->pid, &wstatus, 0, NULL);
-
 	      return ptid_t (inf->pid);
 	    }
