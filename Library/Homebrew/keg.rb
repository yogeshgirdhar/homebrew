require 'extend/pathname'

class Keg < Pathname
  def initialize path
    super path
    raise "#{to_s} is not a valid keg" unless parent.parent.realpath == HOMEBREW_CELLAR.realpath
    raise "#{to_s} is not a directory" unless directory?
  end

  # locale-specific directories have the form language[_territory][.codeset][@modifier]
  LOCALEDIR_RX = /(locale|man)\/([a-z]{2}|C|POSIX)(_[A-Z]{2})?(\.[a-zA-Z\-0-9]+(@.+)?)?/
  INFOFILE_RX = %r[info/[^.].*?\.info$]

  # if path is a file in a keg then this will return the containing Keg object
  def self.for path
    path = path.realpath
    while not path.root?
      return Keg.new(path) if path.parent.parent == HOMEBREW_CELLAR.realpath
      path = path.parent.realpath # realpath() prevents root? failing
    end
    raise NotAKegError, "#{path} is not inside a keg"
  end

  def uninstall
    chmod_R 0777 # ensure we have permission to delete
    rmtree
    parent.rmdir_if_possible
  end

  def unlink
    n=0
    Pathname.new(self).find do |src|
      next if src == self
      dst=HOMEBREW_PREFIX+src.relative_path_from(self)
      next unless dst.symlink?
      dst.uninstall_info if dst.to_s =~ INFOFILE_RX and ENV['HOMEBREW_KEEP_INFO']
      dst.unlink
      dst.parent.rmdir_if_possible
      n+=1
      Find.prune if src.directory?
    end
    linked_keg_record.unlink if linked_keg_record.exist?
    n
  end

  def fname
    parent.basename.to_s
  end

  def linked_keg_record
    @linked_keg_record ||= HOMEBREW_REPOSITORY/"Library/LinkedKegs"/fname
  end

  def linked?
    linked_keg_record.directory? and self == linked_keg_record.realpath
  end

  def link
    raise "Cannot link #{fname}\nAnother version is already linked: #{linked_keg_record.realpath}" if linked_keg_record.directory?

    $n=0
    $d=0

    share_mkpaths=%w[aclocal doc info locale man]+(1..8).collect{|x|"man/man#{x}"}
    # cat pages are rare, but exist so the directories should be created
    share_mkpaths << (1..8).collect{ |x| "man/cat#{x}" }

    # yeah indeed, you have to force anything you need in the main tree into
    # these dirs REMEMBER that *NOT* everything needs to be in the main tree
    link_dir('etc') {:mkpath}
    link_dir('bin') { |path| :skip if path.directory? }
    link_dir('sbin') { |path| :skip if path.directory? }
    link_dir('include') {:link}

    link_dir('share') do |path|
      case path.to_s
      when 'locale/locale.alias' then :skip
      when INFOFILE_RX then :info if ENV['HOMEBREW_KEEP_INFO']
      when LOCALEDIR_RX then :mkpath
      when *share_mkpaths then :mkpath
      else :link
      end
    end

    link_dir('lib') do |path|
      case path.to_s
      when 'charset.alias' then :skip
      # pkg-config database gets explicitly created
      when 'pkgconfig' then :mkpath
      # lib/language folders also get explicitly created
      when /^gdk-pixbuf/ then :mkpath
      when 'ghc' then :mkpath
      when 'lua' then :mkpath
      when 'node' then :mkpath
      when /^ocaml/ then :mkpath
      when /^perl5/ then :mkpath
      when 'php' then :mkpath
      when /^python[23]\.\d$/ then :mkpath
      when 'ruby' then :mkpath
      # Everything else is symlinked to the cellar
      else :link
      end
    end

    (HOMEBREW_REPOSITORY/"Library/LinkedKegs"/fname).make_relative_symlink(self)

    return $n+$d
  end

protected
  def resolve_any_conflicts dst
    # if it isn't a directory then a severe conflict is about to happen. Let
    # it, and the exception that is generated will message to the user about
    # the situation
    if dst.symlink? and dst.directory?
      src = (dst.parent+dst.readlink).cleanpath
      keg = Keg.for(src)
      dst.unlink
      keg.link_dir(src) { :mkpath }
      return true
    end
  rescue NotAKegError
    puts "Won't resolve conflicts for symlink #{dst} as it doesn't resolve into the Cellar" if ARGV.verbose?
  end

  # symlinks the contents of self+foo recursively into /usr/local/foo
  def link_dir foo
    root = self+foo
    return unless root.exist?

    root.find do |src|
      next if src == root

      dst = HOMEBREW_PREFIX+src.relative_path_from(self)
      dst.extend ObserverPathnameExtension

      if src.file?
        Find.prune if File.basename(src) == '.DS_Store'

        case yield src.relative_path_from(root)
        when :skip
          Find.prune
        when :info
          dst.make_relative_symlink(src)
          dst.install_info
        else
          dst.make_relative_symlink(src)
        end
      elsif src.directory?
        # if the dst dir already exists, then great! walk the rest of the tree tho
        next if dst.directory? and not dst.symlink?

        # no need to put .app bundles in the path, the user can just use
        # spotlight, or the open command and actual mac apps use an equivalent
        Find.prune if src.extname.to_s == '.app'

        case yield src.relative_path_from(root)
        when :skip
          Find.prune
        when :mkpath
          dst.mkpath unless resolve_any_conflicts(dst)
        else
          unless resolve_any_conflicts(dst)
            dst.make_relative_symlink(src)
            Find.prune
          end
        end
      end
    end
  end
end

require 'keg_fix_install_names'
