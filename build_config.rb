def gem_config(conf)

  Dir.glob("#{root}/mrbgems/mruby-*/mrbgem.rake") do |x|
    g = File.basename File.dirname x
    conf.gem :core => g unless g =~ /^mruby-(bin-.+|test)$/
  end

  conf.gem 'mrbgems/mruby-io-dup2'
  conf.gem 'mrbgems/mruby-io-fcntl'
  conf.gem 'mrbgems/mruby-process-pgrp'
  conf.gem 'mrbgems/mruby-signal-trap'
  conf.gem 'mrbgems/mruby-reddish-parser'
  conf.gem 'mrbgems/mruby-ruby-exec'
  conf.gem mgem: 'mruby-dir'
  conf.gem mgem: 'mruby-dir-glob'
  conf.gem mgem: 'mruby-file-stat'
  conf.gem mgem: 'mruby-env'
  conf.gem mgem: 'mruby-onig-regexp' do |c|
    c.cc.flags << '-std=gnu99 -Wno-declaration-after-statement'
  end
  conf.gem github: 'buty4649/mruby-process', branch: 'improve-process-exec'
  conf.gem github: 'buty4649/mruby-getopts', branch: 'add-prog-name'
  conf.gem github: 'buty4649/mruby-linenoise', branch: 'raise-ctrl-c'
  conf.gem github: 'haconiwa/mruby-exec'
  conf.gem github: 'ij/mruby-require'

  conf.gem github: "kou/mruby-pp"
end

MRuby::Build.new do |conf|
  toolchain :gcc

  conf.enable_bintest
  conf.enable_debug
  #conf.enable_test

  # be sure to include this gem (the cli app)
  conf.gem File.expand_path(File.dirname(__FILE__))

  gem_config(conf)
end

MRuby::Build.new('fdtest') do |conf|
  toolchain :gcc

  conf.gem 'mrbgems/mruby-bin-fdtest'
  conf.gem mgem: 'mruby-dir-glob'
  conf.gem mgem: 'mruby-onig-regexp' do |c|
    c.cc.flags << '-std=gnu99 -Wno-declaration-after-statement -Wdiscarded-qualifiers'
  end
end

MRuby::Build.new('sigtest') do |conf|
  toolchain :gcc

  conf.gem 'mrbgems/mruby-bin-sigtest'
  conf.gem mgem: 'mruby-io'
  conf.gem mgem: 'mruby-process'
  conf.gem github: 'buty4649/mruby-signal-thread', branch: 'reset-sigmask'
end
