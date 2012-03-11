class Volumes
  def initialize
    @volumes = []
    raw_mounts=`/sbin/mount`
    raw_mounts.split("\n").each do |line|
      case line
      when /^(.+) on (\S+) \(/
        @volumes << [$1, $2]
      end
    end
    # Sort volumes by longest path prefix first
    @volumes.sort! {|a,b| b[1].length <=> a[1].length}
  end

  def which path
    @volumes.each_index do |i|
      vol = @volumes[i]
      return i if vol[1].start_with? path.to_s
    end

    return -1
  end
end


class Checks
  # Sorry for the lack of an indent here, the diff would have been unreadable.

def remove_trailing_slash s
  (s[s.length-1] == '/') ? s[0,s.length-1] : s
end


def path_folders
  ENV['PATH'].split(':').collect{|p| remove_trailing_slash(File.expand_path(p))}.uniq
end


# Installing MacGPG2 interferes with Homebrew in a big way
# http://sourceforge.net/projects/macgpg2/files/
def check_for_macgpg2
  if File.exist? "/Applications/start-gpg-agent.app" or
     File.exist? "/Library/Receipts/libiconv1.pkg"
    <<-EOS.undent
      You may have installed MacGPG2 via the package installer.
      Several other checks in this script will turn up problems, such as stray
      dylibs in /usr/local and permissions issues with share and man in /usr/local/.
    EOS
  end
end

def check_for_stray_dylibs
  unbrewed_dylibs = Dir['/usr/local/lib/*.dylib'].select { |f| File.file? f and not File.symlink? f }

  # Dylibs which are generally OK should be added to this list,
  # with a short description of the software they come with.
  white_list = {
    "libfuse.2.dylib" => "MacFuse",
    "libfuse_ino64.2.dylib" => "MacFuse"
  }

  bad_dylibs = unbrewed_dylibs.reject {|d| white_list.key? File.basename(d) }
  return if bad_dylibs.empty?

  s = <<-EOS.undent
    Unbrewed dylibs were found in /usr/local/lib.
    If you didn't put them there on purpose they could cause problems when
    building Homebrew formulae, and may need to be deleted.

    Unexpected dylibs:
  EOS
  bad_dylibs.each { |f| s << "    #{f}" }
  s
end

def check_for_stray_static_libs
  unbrewed_alibs = Dir['/usr/local/lib/*.a'].select { |f| File.file? f and not File.symlink? f }
  return if unbrewed_alibs.empty?

  s = <<-EOS.undent
    Unbrewed static libraries were found in /usr/local/lib.
    If you didn't put them there on purpose they could cause problems when
    building Homebrew formulae, and may need to be deleted.

    Unexpected static libraries:
  EOS
  unbrewed_alibs.each{ |f| s << "    #{f}" }
  s
end

def check_for_stray_pcs
  unbrewed_pcs = Dir['/usr/local/lib/pkgconfig/*.pc'].select { |f| File.file? f and not File.symlink? f }

  # Package-config files which are generally OK should be added to this list,
  # with a short description of the software they come with.
  white_list = {
    "fuse.pc" => "MacFuse",
  }

  bad_pcs = unbrewed_pcs.reject {|d| white_list.key? File.basename(d) }
  return if bad_pcs.empty?

  s = <<-EOS.undent
    Unbrewed .pc files were found in /usr/local/lib/pkgconfig.
    If you didn't put them there on purpose they could cause problems when
    building Homebrew formulae, and may need to be deleted.

    Unexpected .pc files:
  EOS
  bad_pcs.each{ |f| s << "    #{f}" }
  s
end

def check_for_stray_las
  unbrewed_las = Dir['/usr/local/lib/*.la'].select { |f| File.file? f and not File.symlink? f }

  white_list = {
    "libfuse.la" => "MacFuse",
    "libfuse_ino64.la" => "MacFuse",
  }

  bad_las = unbrewed_las.reject {|d| white_list.key? File.basename(d) }
  return if bad_las.empty?

  s = <<-EOS.undent
    Unbrewed .la files were found in /usr/local/lib.
    If you didn't put them there on purpose they could cause problems when
    building Homebrew formulae, and may need to be deleted.

    Unexpected .la files:
  EOS
  bad_las.each{ |f| s << "    #{f}" }
  s
end

def check_for_x11
  unless x11_installed?
    <<-EOS.undent
      X11 not installed.
      You don't have X11 installed as part of your OS X installation.
      This is not required for all formulae, but is expected by some.
    EOS
  end
end

def check_for_nonstandard_x11
  x11 = Pathname.new('/usr/X11')
  if x11.symlink?
    <<-EOS.undent
      /usr/X11 is a symlink
      Homebrew's X11 support has only be tested with Apple's X11.
      In particular, "XQuartz" and "XDarwin" are not known to be compatible.
    EOS
  end
end

def check_for_other_package_managers
  if macports_or_fink_installed?
    <<-EOS.undent
      You have Macports or Fink installed.
      This can cause trouble. You don't have to uninstall them, but you may like to
      try temporarily moving them away, eg.

        sudo mv /opt/local ~/macports
    EOS
  end
end

def check_gcc_42
  if MacOS.gcc_42_build_version == nil
    # Don't show this warning on Xcode 4.2+
    if MacOS.xcode_version < "4.2"
      "We couldn't detect gcc 4.2.x. Some formulae require this compiler."
    end
  elsif MacOS.gcc_42_build_version < RECOMMENDED_GCC_42
    <<-EOS.undent
      Your gcc 4.2.x version is older than the recommended version.
      It may be advisable to upgrade to the latest release of Xcode.
    EOS
  end
end

def check_xcode_exists
  if MacOS.xcode_version == nil
      <<-EOS.undent
        We couldn't detect any version of Xcode.
        If you downloaded Xcode from the App Store, you may need to run the installer.
      EOS
  elsif MacOS.xcode_version < "4.0"
    if MacOS.gcc_40_build_version == nil
      "We couldn't detect gcc 4.0.x. Some formulae require this compiler."
    elsif MacOS.gcc_40_build_version < RECOMMENDED_GCC_40
      <<-EOS.undent
        Your gcc 4.0.x version is older than the recommended version.
        It may be advisable to upgrade to the latest release of Xcode.
      EOS
    end
  end
end

def check_for_latest_xcode
  # the check_xcode_exists check is enough
  return if MacOS.xcode_version.nil?

  latest_xcode = case MacOS.version
    when 10.5 then "3.1.4"
    when 10.6 then "3.2.6"
    else "4.3"
  end
  if MacOS.xcode_version < latest_xcode then <<-EOS.undent
    You have Xcode #{MacOS.xcode_version}, which is outdated.
    Please install Xcode #{latest_xcode}.
    EOS
  end
end

def check_cc
  unless File.exist? '/usr/bin/cc'
    <<-EOS.undent
      You have no /usr/bin/cc.
      This means you probably can't build *anything*. You need to install the CLI
      Tools for Xcode. You can either download this from http://connect.apple.com/
      or install them from inside Xcode’s preferences. Homebrew does not require
      all of Xcode! You only need the CLI tools package!
    EOS
  end
end

def __check_subdir_access base
  target = HOMEBREW_PREFIX+base
  return unless target.exist?

  cant_read = []

  target.find do |d|
    next unless d.directory?
    cant_read << d unless d.writable?
  end

  cant_read.sort!
  if cant_read.length > 0 then
    s = <<-EOS.undent
    Some directories in #{target} aren't writable.
    This can happen if you "sudo make install" software that isn't managed
    by Homebrew. If a brew tries to add locale information to one of these
    directories, then the install will fail during the link step.
    You should probably `chown` them:

    EOS
    cant_read.each{ |f| s << "    #{f}\n" }
    s
  end
end

def check_access_usr_local
  return unless HOMEBREW_PREFIX.to_s == '/usr/local'

  unless Pathname('/usr/local').writable? then <<-EOS.undent
    The /usr/local directory is not writable.
    Even if this directory was writable when you installed Homebrew, other
    software may change permissions on this directory. Some versions of the
    "InstantOn" component of Airfoil are known to do this.

    You should probably change the ownership and permissions of /usr/local
    back to your user account.
    EOS
  end
end

def check_access_share_locale
  __check_subdir_access 'share/locale'
end

def check_access_share_man
  __check_subdir_access 'share/man'
end

def __check_folder_access base, msg
  folder = HOMEBREW_PREFIX+base
  if folder.exist? and not folder.writable?
    <<-EOS.undent
      #{folder} isn't writable.
      This can happen if you "sudo make install" software that isn't managed
      by Homebrew.

      #{msg}

      You should probably `chown` #{folder}
    EOS
  end
end

def check_access_pkgconfig
  __check_folder_access 'lib/pkgconfig',
  'If a brew tries to write a .pc file to this directory, the install will\n'+
  'fail during the link step.'
end

def check_access_include
  __check_folder_access 'include',
  'If a brew tries to write a header file to this directory, the install will\n'+
  'fail during the link step.'
end

def check_access_etc
  __check_folder_access 'etc',
  'If a brew tries to write a file to this directory, the install will\n'+
  'fail during the link step.'
end

def check_access_share
  __check_folder_access 'share',
  'If a brew tries to write a file to this directory, the install will\n'+
  'fail during the link step.'
end

def check_usr_bin_ruby
  if /^1\.9/.match RUBY_VERSION
    <<-EOS.undent
      Ruby version #{RUBY_VERSION} is unsupported.
      Homebrew is developed and tested on Ruby 1.8.x, and may not work correctly
      on other Rubies. Patches are accepted as long as they don't break on 1.8.x.
    EOS
  end
end

def check_homebrew_prefix
  unless HOMEBREW_PREFIX.to_s == '/usr/local'
    <<-EOS.undent
      Your Homebrew is not installed to /usr/local
      You can install Homebrew anywhere you want, but some brews may only build
      correctly if you install in /usr/local. Sorry!
    EOS
  end
end

def check_xcode_prefix
  prefix = MacOS.xcode_prefix
  return if prefix.nil?
  if prefix.to_s.match(' ')
    <<-EOS.undent
      Xcode is installed to a directory with a space in the name.
      This will cause some formulae, such as libiconv, to fail to build.
    EOS
  end
end

def check_xcode_select_path
  path = `xcode-select -print-path 2>/dev/null`.chomp
  unless File.directory? path and File.file? "#{path}/usr/bin/xcodebuild"
    # won't guess at the path they should use because it's too hard to get right
    # We specify /Applications/Xcode.app/Contents/Developer even though
    # /Applications/Xcode.app should work because people don't install the new CLI
    # tools and then it doesn't work. Lets hope the location doesn't change in the
    # future.

    <<-EOS.undent
      Your Xcode is configured with an invalid path.
      You should change it to the correct path. Please note that there is no correct
      path at this time if you have *only* installed the Command Line Tools for Xcode.
      If your Xcode is pre-4.3 or you installed the whole of Xcode 4.3 then one of
      these is (probably) what you want:

          sudo xcode-select -switch /Developer
          sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
    EOS
  end
end

def check_user_path_1
  $seen_prefix_bin = false
  $seen_prefix_sbin = false
  seen_usr_bin = false

  out = nil

  path_folders.each do |p| case p
    when '/usr/bin'
      seen_usr_bin = true
      unless $seen_prefix_bin
        # only show the doctor message if there are any conflicts
        # rationale: a default install should not trigger any brew doctor messages
        conflicts = Dir["#{HOMEBREW_PREFIX}/bin/*"].
            map{ |fn| File.basename fn }.
            select{ |bn| File.exist? "/usr/bin/#{bn}" }

        if conflicts.size > 0
          out = <<-EOS.undent
            /usr/bin occurs before #{HOMEBREW_PREFIX}/bin
            This means that system-provided programs will be used instead of those
            provided by Homebrew. The following tools exist at both paths:

                #{conflicts * "\n                "}

            Consider ammending your PATH so that #{HOMEBREW_PREFIX}/bin
            is ahead of /usr/bin in your PATH.
          EOS
        end
      end
    when "#{HOMEBREW_PREFIX}/bin"
      $seen_prefix_bin = true
    when "#{HOMEBREW_PREFIX}/sbin"
      $seen_prefix_sbin = true
    end
  end
  out
end

def check_user_path_2
  unless $seen_prefix_bin
    <<-EOS.undent
      Homebrew's bin was not found in your path.
      Consider ammending your PATH variable so it contains:
        #{HOMEBREW_PREFIX}/bin
    EOS
  end
end

def check_user_path_3
  # Don't complain about sbin not being in the path if it doesn't exist
  sbin = (HOMEBREW_PREFIX+'sbin')
  if sbin.directory? and sbin.children.length > 0
    unless $seen_prefix_sbin
      <<-EOS.undent
        Homebrew's sbin was not found in your path.
        Consider ammending your PATH variable so it contains:
          #{HOMEBREW_PREFIX}/sbin
      EOS
    end
  end
end

def check_which_pkg_config
  binary = `/usr/bin/which pkg-config`.chomp
  return if binary.empty?

  unless binary == "#{HOMEBREW_PREFIX}/bin/pkg-config"
    <<-EOS.undent
      You have a non-brew 'pkg-config' in your PATH:
        #{binary}

      `./configure` may have problems finding brew-installed packages using
      this other pkg-config.
    EOS
  end
end

def check_pkg_config_paths
  binary = `/usr/bin/which pkg-config`.chomp
  return if binary.empty?

  # Use the debug output to determine which paths are searched
  pkg_config_paths = []

  debug_output = `pkg-config --debug 2>&1`
  debug_output.split("\n").each do |line|
    line =~ /Scanning directory '(.*)'/
    pkg_config_paths << $1 if $1
  end

  # Check that all expected paths are being searched
  unless pkg_config_paths.include? "/usr/X11/lib/pkgconfig"
    <<-EOS.undent
      Your pkg-config is not checking "/usr/X11/lib/pkgconfig" for packages.
      Earlier versions of the pkg-config formula did not add this path
      to the search path, which means that other formula may not be able
      to find certain dependencies.

      To resolve this issue, re-brew pkg-config with:
        brew rm pkg-config && brew install pkg-config
    EOS
  end
end

def check_for_gettext
  if %w[lib/libgettextlib.dylib
        lib/libintl.dylib
        include/libintl.h ].any? { |f| File.exist? "#{HOMEBREW_PREFIX}/#{f}" }
    <<-EOS.undent
      gettext was detected in your PREFIX.
      The gettext provided by Homebrew is "keg-only", meaning it does not
      get linked into your PREFIX by default.

      If you `brew link gettext` then a large number of brews that don't
      otherwise have a `depends_on 'gettext'` will pick up gettext anyway
      during the `./configure` step.

      If you have a non-Homebrew provided gettext, other problems will happen
      especially if it wasn't compiled with the proper architectures.
    EOS
  end
end

def check_for_iconv
  if %w[lib/libiconv.dylib
        include/iconv.h ].any? { |f| File.exist? "#{HOMEBREW_PREFIX}/#{f}" }
    <<-EOS.undent
      libiconv was detected in your PREFIX.
      Homebrew doesn't provide a libiconv formula, and expects to link against
      the system version in /usr/lib.

      If you have a non-Homebrew provided libiconv, many formulae will fail
      to compile or link, especially if it wasn't compiled with the proper
      architectures.
    EOS
  end
end

def check_for_config_scripts
  real_cellar = HOMEBREW_CELLAR.exist? && HOMEBREW_CELLAR.realpath

  config_scripts = []

  path_folders.each do |p|
    next if ['/usr/bin', '/usr/sbin', '/usr/X11/bin', '/usr/X11R6/bin', "#{HOMEBREW_PREFIX}/bin", "#{HOMEBREW_PREFIX}/sbin", "/opt/X11/bin"].include? p
    next if p =~ %r[^(#{real_cellar.to_s}|#{HOMEBREW_CELLAR.to_s})] if real_cellar

    configs = Dir["#{p}/*-config"]
    # puts "#{p}\n    #{configs * ' '}" unless configs.empty?
    config_scripts << [p, configs.collect {|p| File.basename(p)}] unless configs.empty?
  end

  unless config_scripts.empty?
    s = <<-EOS.undent
      "config" scripts exist outside your system or Homebrew directories.
      `./configure` scripts often look for *-config scripts to determine if
      software packages are installed, and what additional flags to use when
      compiling and linking.

      Having additional scripts in your path can confuse software installed via
      Homebrew if the config script overrides a system or Homebrew provided
      script of the same name. We found the following "config" scripts:

    EOS

    config_scripts.each do |pair|
      dn = pair[0]
      pair[1].each do |fn|
        s << "    #{dn}/#{fn}\n"
      end
    end
    s
  end
end

def check_for_dyld_vars
  if ENV['DYLD_LIBRARY_PATH']
    <<-EOS.undent
      Setting DYLD_LIBRARY_PATH can break dynamic linking.
      You should probably unset it.
    EOS
  end
end

def check_for_symlinked_cellar
  if HOMEBREW_CELLAR.symlink?
    <<-EOS.undent
      Symlinked Cellars can cause problems.
      Your Homebrew Cellar is a symlink: #{HOMEBREW_CELLAR}
                      which resolves to: #{HOMEBREW_CELLAR.realpath}

      The recommended Homebrew installations are either:
      (A) Have Cellar be a real directory inside of your HOMEBREW_PREFIX
      (B) Symlink "bin/brew" into your prefix, but don't symlink "Cellar".

      Older installations of Homebrew may have created a symlinked Cellar, but this can
      cause problems when two formula install to locations that are mapped on top of each
      other during the linking step.
    EOS
  end
end

def check_for_multiple_volumes
  return unless HOMEBREW_CELLAR.exist?
  volumes = Volumes.new

  # Find the volumes for the TMP folder & HOMEBREW_CELLAR
  real_cellar = HOMEBREW_CELLAR.realpath

  tmp_prefix = ENV['HOMEBREW_TEMP'] || '/tmp'
  tmp = Pathname.new `/usr/bin/mktemp -d #{tmp_prefix}/homebrew-brew-doctor-XXXX`.strip
  real_temp = tmp.realpath.parent

  where_cellar = volumes.which real_cellar
  where_temp = volumes.which real_temp

  Dir.delete tmp

  unless where_cellar == where_temp then <<-EOS.undent
    Your Cellar and TEMP directories are on different volumes.
    OS X won't move relative symlinks across volumes unless the target file already
    exists. Brews known to be affected by this are Git and Narwhal.

    You should set the "HOMEBREW_TEMP" environmental variable to a suitable
    directory on the same volume as your Cellar.
    EOS
  end
end

def check_for_git
  unless system "/usr/bin/which -s git" then <<-EOS.undent
    Git could not be found in your PATH.
    Homebrew uses Git for several internal functions, and some formulae use Git
    checkouts instead of stable tarballs. You may want to install Git:
      brew install git
    EOS
  end
end

def check_git_newline_settings
  return unless system "/usr/bin/which -s git"

  autocrlf = `git config --get core.autocrlf`.chomp
  safecrlf = `git config --get core.safecrlf`.chomp

  if autocrlf == 'input' and safecrlf == 'true' then <<-EOS.undent
    Suspicious Git newline settings found.

    The detected Git newline settings can cause checkout problems:
      core.autocrlf = #{autocrlf}
      core.safecrlf = #{safecrlf}

    If you are not routinely dealing with Windows-based projects,
    consider removing these settings.
    EOS
  end
end

def check_for_autoconf
  return if MacOS.xcode_version >= "4.3"

  autoconf = `/usr/bin/which autoconf`.chomp
  safe_autoconfs = %w[/usr/bin/autoconf /Developer/usr/bin/autoconf]
  unless autoconf.empty? or safe_autoconfs.include? autoconf then <<-EOS.undent
    An "autoconf" in your path blocks the Xcode-provided version at:
      #{autoconf}

    This custom autoconf may cause some Homebrew formulae to fail to compile.
    EOS
  end
end

def __check_linked_brew f
  links_found = []

  Pathname.new(f.prefix).find do |src|
    dst=HOMEBREW_PREFIX+src.relative_path_from(f.prefix)
    next unless dst.symlink?

    dst_points_to = dst.realpath()
    next unless dst_points_to.to_s == src.to_s

    if src.directory?
      Find.prune
    else
      links_found << dst
    end
  end

  return links_found
end

def check_for_linked_kegonly_brews
  require 'formula'

  warnings = Hash.new

  Formula.all.each do |f|
    next unless f.keg_only? and f.installed?
    links = __check_linked_brew f
    warnings[f.name] = links unless links.empty?
  end

  unless warnings.empty?
    s = <<-EOS.undent
    Some keg-only formula are linked into the Cellar.
    Linking a keg-only formula, such as gettext, into the cellar with
    `brew link f` will cause other formulae to detect them during the
    `./configure` step. This may cause problems when compiling those
    other formulae.

    Binaries provided by keg-only formulae may override system binaries
    with other strange results.

    You may wish to `brew unlink` these brews:

    EOS
    warnings.keys.each{ |f| s << "    #{f}\n" }
    s
  end
end

def check_for_MACOSX_DEPLOYMENT_TARGET
  target_var = ENV['MACOSX_DEPLOYMENT_TARGET']
  if target_var and target_var != MACOS_VERSION.to_s then <<-EOS.undent
    MACOSX_DEPLOYMENT_TARGET was set to #{target_var}
    This is used by Fink, but having it set to a value different from the
    current system version (#{MACOS_VERSION}) can cause problems, compiling
    Git for instance, and should probably be removed.
    EOS
  end
end

def check_for_other_frameworks
  # Other frameworks that are known to cause problems when present
  %w{Mono.framework expat.framework libexpat.framework}.
    map{ |frmwrk| "/Library/Frameworks/#{frmwrk}" }.
    select{ |frmwrk| File.exist? frmwrk }.
    map do |frmwrk| <<-EOS.undent
      #{frmwrk} detected
      This can be picked up by CMake's build system and likely cause the build to
      fail. You may need to move this file out of the way to compile CMake.
      EOS
    end.join
end

def check_tmpdir
  tmpdir = ENV['TMPDIR']
  "TMPDIR #{tmpdir.inspect} doesn't exist." unless tmpdir.nil? or File.directory? tmpdir
end

def check_missing_deps
  s = []
  `brew missing`.each_line do |line|
    line =~ /(.*): (.*)/
    $2.split.each do |dep|
        s << dep unless s.include? dep
    end
  end
  if s.length > 0 then <<-EOS.undent
    Some installed formula are missing dependencies.
    You should `brew install` the missing dependencies:

        brew install #{s * " "}

    Run `brew missing` for more details.
    EOS
  end
end

def check_git_status
  return unless system "/usr/bin/which -s git"
  HOMEBREW_REPOSITORY.cd do
    unless `git status -s -- Library/Homebrew/ 2>/dev/null`.chomp.empty? then <<-EOS.undent
      You have uncommitted modifications to Homebrew's core.
      Unless you know what you are doing, you should run:
        cd #{HOMEBREW_REPOSITORY} && git reset --hard
      EOS
    end
  end
end

def check_for_leopard_ssl
  if MacOS.leopard? and not ENV['GIT_SSL_NO_VERIFY']
    <<-EOS.undent
      The version of libcurl provided with Mac OS X Leopard has outdated
      SSL certificates.

      This can cause problems when running Homebrew commands that use Git to
      fetch over HTTPS, e.g. `brew update` or installing formulae that perform
      Git checkouts.

      You can force Git to ignore these errors by setting GIT_SSL_NO_VERIFY.
        export GIT_SSL_NO_VERIFY=1
    EOS
  end
end

def check_git_version
  # see https://github.com/blog/642-smart-http-support
  return unless system "/usr/bin/which -s git"
  `git --version`.chomp =~ /git version (\d)\.(\d)\.(\d)/

  if $2.to_i < 6 or $2.to_i == 6 and $3.to_i < 6 then <<-EOS.undent
    An outdated version of Git was detected in your PATH.
    Git 1.6.6 or newer is required to perform checkouts over HTTP from GitHub.
    Please upgrade: brew upgrade git
    EOS
  end
end

def check_for_enthought_python
  if system "/usr/bin/which -s enpkg" then <<-EOS.undent
    Enthought Python was found in your PATH.
    This can cause build problems, as this software installs its own
    copies of iconv and libxml2 into directories that are picked up by
    other build systems.
    EOS
  end
end

def check_for_bad_python_symlink
  return unless system "/usr/bin/which -s python"
  # Indeed Python --version outputs to stderr (WTF?)
  `python --version 2>&1` =~ /Python (\d+)\./
  unless $1 == "2" then <<-EOS.undent
    python is symlinked to python#$1
    This will confuse build scripts and in general lead to subtle breakage.
    EOS
  end
end

def check_for_outdated_homebrew
  HOMEBREW_REPOSITORY.cd do
    timestamp = if File.directory? ".git"
      `git log -1 --format="%ct" HEAD`.to_i
    else
      (HOMEBREW_REPOSITORY/"Library").mtime.to_i
    end

    if Time.now.to_i - timestamp > 60 * 60 * 24 then <<-EOS.undent
      Your Homebrew is outdated
      You haven't updated for at least 24 hours, this is a long time in brewland!
      EOS
    end
  end
end

end # end class Checks

module Homebrew extend self
  def doctor
    raring_to_brew = true

    checks = Checks.new

    checks.methods.select{ |method| method =~ /^check_/ }.sort.each do |method|
      out = checks.send(method)
      unless out.nil? or out.empty?
        puts unless raring_to_brew
        lines = out.to_s.split('\n')
        opoo lines.shift
        puts lines
        raring_to_brew = false
      end
    end

    puts "Your system is raring to brew." if raring_to_brew
    exit raring_to_brew ? 0 : 1
  end
end
