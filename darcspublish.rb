#!/usr/bin/env ruby

require 'net/ftp'
require 'fileutils'

def assureDarcsRepo
  if !File.directory? '_darcs' then
    $stderr.puts "*** This Directory is not a darcs repository!"
    exit 1
  end
end

def loadProfile(profile = nil)
  config = {}
  files = [ ENV['HOME'] + '/.darcspublish', '_darcs/prefs/ftpdata', '_darcs/prefs/darcspublish' ]
  if profile then files.push '_darcs/prefs/darcspublish.' + profile end
  print "*** Reading configuration:"
  files.each do |f|
    next unless File.exists?(f)
    print " #{f}"
    next unless handle = File.new(f, 'r')
    handle.each do |l|
      key, value = l.split(/=/, 2)
      key.strip!
      next unless !key.empty?
      # emulate un-setting shell variables
      if (value == nil || value.strip.empty?) and config.has_key? key then
        config.delete key
        next
      end
      config[key] = value.strip.sub(/^"(.*)"$/, '\1')
    end
  end
  puts 

  if !config.has_key? 'USER' or
     !config.has_key? 'PASSWORD' then
    if File.exists? ENV['HOME'] + '/.netrc' and
       handle = File.new(ENV['HOME'] + '/.netrc', 'r') then
      handle.each do |l|
        tokens = l.split(/\s+/, 6)
        if tokens[1] == config['SERVER'] then
          config['USER'] = tokens[3]
          config['PASSWORD'] = tokens[5]
        end
      end
    end
  end

  if !config.has_key? 'SERVER' or
     !config.has_key? 'USER' or !config.has_key? 'PASSWORD' or
     (!config.has_key? 'BASEDIR' and !config.has_key? 'DIR') then
    $stderr.puts "*** Configuration incomplete."
    exit 1
  end

  return config
end

def createTempDir
  if File.exists? '/tmp/darcspublish' then
    FileUtils.rm_rf '/tmp/darcspublish'
  end
  FileUtils.mkdir '/tmp/darcspublish'
  return '/tmp/darcspublish'
end

def main
  assureDarcsRepo
  cfg = loadProfile
  cfg['PROJECT'] = File.basename(Dir.pwd)
  if cfg.has_key?('DIR') then
    cfg['REMOTEDIR'] = cfg['DIR']
  else
    cfg['REMOTEDIR'] = cfg['BASEDIR'] + '/' + cfg['PROJECT']
  end

  $tempDir = createTempDir

  if !cfg.has_key? 'PRISTINE' or 
     (cfg.has_key? 'PRISTINE' and !File.directory? '_darcs/pristine') then
    print "*** Creating clean working copy: "
    if File.readable? '_darcs/prefs/defaultrepo' then
      FileUtils.cp '_darcs/prefs/defaultrepo', "#{$tempDir}/defaultrepo"
    end

    exit 1 unless system 'darcs put ' + (cfg['EXCLUDEPRISTINE'].empty? ? '' : '--no-pristine-tree ') + $tempDir + '/darcscopy >/dev/null'
    puts "ok"

    if File.readable? '_darcs/prefs/email' then
      FileUtils.cp "_darcs/prefs/email", "#{$tempDir}/darcscopy/_darcs/prefs"
    end
    if File.readable? "#{$tempDir}/defaultrepo" then
      FileUtils.cp "#{$tempDir}/defaultrepo", "_darcs/prefs/"
    end

    # if we're simulating PRISTINE, we need to EXCLUDE _darcs
    cfg['EXCLUDE'] = '_darcs ' + (cfg.has_key?('EXCLUDE') ? cfg['EXCLUDE'] : '')
    # if someone asks, say NO, as we're only simulating it :)
    cfg.delete 'PRISTINE'
  end

  FileUtils.touch $tempDir + '/rc'
  FileUtils.chmod 0600, $tempDir + '/rc'
  rc = File.new($tempDir + '/rc', 'w')
  rc.puts 'site darcspublish',
          '  server ' + cfg['SERVER'],
          '  username ' + cfg['USER'],
          '  password ' + cfg['PASSWORD'],
          '  remote ' + cfg['REMOTEDIR'],
          (cfg.has_key? 'PRISTINE') ?
          "  local #{Dir.pwd}/_darcs/pristine" :
          "  local #{$tempDir}/darcscopy",
          '  protocol ftp',
          '  state checksum',
          '  permissions all',
          '  symlinks ignore'
  cfg['EXCLUDE'].split(/\s+/).each do |i|
    rc.puts "  exclude #{i}"
  end unless !cfg.has_key? 'EXCLUDE'
  rc.close

  if !File.directory? '_darcs/sitecopystate' then
    FileUtils.mkdir '_darcs/sitecopystate'
  end
  FileUtils.chmod 0700, '_darcs/sitecopystate'

  if cfg.has_key? 'UPLOADSTATE' then
    print "*** Attempting to download state file: "
    Net::FTP.open(cfg['SERVER'], cfg['USER'], cfg['PASSWORD']) do |ftp|
      ftp.passive = true
      begin
        ftp.getbinaryfile "#{cfg['REMOTEDIR']}/.darcspublishstate",
                          "#{$tempDir}/statefile"
        puts "ok"
        FileUtils.mv "#{$tempDir}/statefile", "_darcs/sitecopystate/darcspublish"
      rescue
        puts "not found"
        FileUtils.rm_rf "#{$tempDir}/statefile"
      end
    end
  end

  if !File.exists? '_darcs/sitecopystate/darcspublish' then
    puts "*** Publishing from here for the first time."
    print "*** Setting up initial state: "
    exit 1 unless system "sitecopy -r #{$tempDir}/rc -p _darcs/sitecopystate -i darcspublish"
    exit 1 unless system "sitecopy -r #{$tempDir}/rc -p _darcs/sitecopystate -f darcspublish"
    puts "ok"
  else
    puts "*** Found state file."
  end

  if cfg.has_key? 'CAREFUL' then
    puts "*** I'm being careful."
    system "sitecopy -r #{$tempDir}/rc -p _darcs/sitecopystate -l darcspublish"
    print "*** PRESS CTRL-C TO CANCEL OR RETURN TO CONTINUE!"
    $stdin.gets
  end
  exit 1 unless system "sitecopy -r #{$tempDir}/rc -p _darcs/sitecopystate -u darcspublish"

  if cfg.has_key? 'UPLOADSTATE' then
    print "*** Uploading state file: "
    Net::FTP.open(cfg['SERVER'], cfg['USER'], cfg['PASSWORD']) do |ftp|
      ftp.passive = true
      begin
        ftp.putbinaryfile '_darcs/sitecopystate/darcspublish',
                          "#{cfg['REMOTEDIR']}/.darcspublishstate"
        puts "ok"
      rescue
        puts "error"
      end
    end
  end

  #puts "*** CONFIGURATION USED ***"
  #cfg.each_pair do |k, v|
  #  puts "#{k}: #{v}"
  #end
end

main
