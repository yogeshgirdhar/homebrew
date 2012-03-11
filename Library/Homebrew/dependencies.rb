## This file defines dependencies and requirements.
##
## A dependency is a formula that another formula needs to install.
## A requirement is something other than a formula that another formula
## needs to be present. This includes external language modules,
## command-line tools in the path, or any arbitrary predicate.
##
## The `depends_on` method in the formula DSL is used to declare
## dependencies and requirements.


# This class is used by `depends_on` in the formula DSL to turn dependency
# specifications into the proper kinds of dependencies and requirements.
class DependencyCollector
  # Define the languages that we can handle as external dependencies.
  LANGUAGE_MODULES = [
    :chicken, :jruby, :lua, :node, :perl, :python, :rbx, :ruby
  ].freeze

  attr_reader :deps, :external_deps

  def initialize
    @deps = Dependencies.new
    @external_deps = []
  end

  def add spec
    case spec
    when String      then @deps << Dependency.new(spec)
    when Formula     then @deps << Dependency.new(spec.name)
    when Dependency  then @deps << spec
    when Requirement then @external_deps << spec
    when Hash
      key, value = spec.shift
      case value
      when Array
        @deps << Dependency.new(key, value)
      when *LANGUAGE_MODULES
        @external_deps << LanguageModuleDependency.new(key, value)
      else
        # :optional, :recommended, :build, :universal and "32bit" are predefined
        @deps << Dependency.new(key, [value])
      end
    else
      raise "Unsupported type #{spec.class} for #{spec}"
    end
  end
end


# A list of formula dependencies.
class Dependencies < Array
  def include? dependency_name
    self.any?{|d| d.name == dependency_name}
  end
end


# A dependency on another Homebrew formula.
class Dependency
  attr_reader :name, :tags

  def initialize name, tags=nil
    @name = name
    tags = [] if tags == nil
    @tags = tags.each {|s| s.to_s}
  end

  def to_s
    @name
  end

  def ==(other_dep)
    @name = other_dep.to_s
  end

  def options
    @tags.select{|p|p.start_with? '--'}
  end
end


# A base class for non-formula requirements needed by formulae.
# A "fatal" requirement is one that will fail the build if it is not present.
# By default, Requirements are non-fatal.
class Requirement
  def satisfied?; false; end
  def fatal?; false; end
  def message; ""; end
end


# A dependency on a language-specific module.
class LanguageModuleDependency < Requirement
  def initialize module_name, type
    @module_name = module_name
    @type = type
  end

  def fatal?; true; end

  def satisfied?
    quiet_system *the_test
  end

  def message; <<-EOS.undent
    Unsatisfied dependency: #{@module_name}
    Homebrew does not provide #{@type.to_s.capitalize} dependencies; install with:
      #{command_line} #{@module_name}
    EOS
  end

  def the_test
    case @type
      when :chicken then %W{/usr/bin/env csi -e (use #{@module_name})}
      when :jruby then %W{/usr/bin/env jruby -rubygems -e require\ '#{@module_name}'}
      when :lua then %W{/usr/bin/env luarocks show #{@module_name}}
      when :node then %W{/usr/bin/env node -e require('#{@module_name}');}
      when :perl then %W{/usr/bin/env perl -e use\ #{@module_name}}
      when :python then %W{/usr/bin/env python -c import\ #{@module_name}}
      when :ruby then %W{/usr/bin/env ruby -rubygems -e require\ '#{@module_name}'}
      when :rbx then %W{/usr/bin/env rbx -rubygems -e require\ '#{@module_name}'}
    end
  end

  def command_line
    case @type
      when :chicken then "chicken-install"
      when :jruby   then "jruby -S gem install"
      when :lua     then "luarocks install"
      when :node    then "npm install"
      when :perl    then "cpan -i"
      when :python  then "easy_install"
      when :rbx     then "rbx gem install"
      when :ruby    then "gem install"
    end
  end
end
