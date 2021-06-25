class Gdb < Formula
  desc "GNU debugger"
  homepage "https://www.gnu.org/software/gdb/"
  url "https://ftp.gnu.org/gnu/gdb/gdb-10.1.tar.xz"
  mirror "https://ftpmirror.gnu.org/gdb/gdb-10.1.tar.xz"
  sha256 "250c419f5130b031328556d66a042173a74ac7f183fa50ed1032aed199eb6499"
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
   
    patch <<BUGFIX_25560_27365
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
BUGFIX_25560_27365
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
# https://sourceware.org/bugzilla/show_bug.cgi?id=24069#c6 (variation)
# https://sourceware.org/bugzilla/show_bug.cgi?id=24069#c14
diff -U3 gdb-10.1-ORIG/gdb/darwin-nat.c gdb-10.1/gdb/darwin-nat.c
--- gdb-10.1-ORIG/gdb/darwin-nat.c	2020-10-24 06:23:02.000000000 +0200
+++ gdb-10.1/gdb/darwin-nat.c	2021-04-07 20:17:15.000000000 +0200
@@ -1055,7 +1053,7 @@ darwin_nat_target::decode_message (mach_msg_header_t *hdr,
     }
   else if (hdr->msgh_id == 0x48)
     {
-      /* MACH_NOTIFY_DEAD_NAME: notification for exit.  */
+      /* MACH_NOTIFY_DEAD_NAME: notification for exit *or* WIFSTOPPED.  */
       int res;
 
       res = darwin_decode_notify_message (hdr, &inf);
@@ -1098,19 +1096,23 @@ darwin_nat_target::decode_message (mach_msg_header_t *hdr,
 		{
 		  status->kind = TARGET_WAITKIND_EXITED;
 		  status->value.integer = WEXITSTATUS (wstatus);
+		  inferior_debug (4, _("darwin_wait: pid=%d exit, status=0x%x\n"),
+				  res_pid, wstatus);
+		}
+	      else if (WIFSTOPPED (wstatus))
+		{
+		  status->kind = TARGET_WAITKIND_IGNORE;
+		  inferior_debug (4, _("darwin_wait: pid %d received WIFSTOPPED\n"), res_pid);
+		  return minus_one_ptid;
 		}
 	      else
 		{
 		  status->kind = TARGET_WAITKIND_SIGNALLED;
 		  status->value.sig = gdb_signal_from_host (WTERMSIG (wstatus));
+		  inferior_debug (4, _("darwin_wait: pid=%d received signal %d\n"),
+			      res_pid, status->value.sig);
 		}
 
-	      inferior_debug (4, _("darwin_wait: pid=%d exit, status=0x%x\n"),
-			      res_pid, wstatus);
-
-	      /* Looks necessary on Leopard and harmless...  */
-	      wait4 (inf->pid, &wstatus, 0, NULL);
-
 	      return ptid_t (inf->pid);
 	    }
 	  else
