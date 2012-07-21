#!/usr/bin/env ruby

#
# = darcspublish.rb — Easily Publish Software and Websites
#
# Author:: Robert Lillack <rob@burningsoda.com>
# Documentation:: http://burningsoda.com/software/darcspublish/
# Copyright:: Copyright (c) 2007—2008 Robert Lillack, burningsoda.com
# License:: 2-clause BSD
#

require 'erb'
require 'fileutils'
require 'net/ftp'
require 'time'

class TemplateInformation
	def initialize(filename = "",
	               changed = Time.now,
	               published = Time.now)
		@filename = filename
		@changed = changed
		@published = published
	end
	
	def get_binding
		return binding
	end
end

def find_mtime(type, directory, filename)
	case type
	when 'plain'
		return File.stat(File.join(directory, filename)).mtime
	when 'darcs'
		return Time.parse(`darcs changes --repodir "#{directory}" "#{filename[1..-1]}"`.split("\n")[2])
        when 'git'
		return Time.at(`git log --format=format:%ct -n1`.to_i)
	else
		raise "find_mtime not supported for repo type #{type}"
	end
end

def checkRepoType
  return ARGV[1] if ARGV[0] == '-t'

  # we allow real repositories to act like plain ones
  if File.readable? '_darcspublish' then
    return 'plain'
  end

  if File.directory? '_darcs' then
    return 'darcs'
  elsif File.directory? '.git' then
    return 'git'
  else
    return 'plain'
  end
end

def loadProfile(profile = nil)
  print "*** Checking repository type: "
  type = checkRepoType
  puts type

  case type
  when 'darcs'
    configfile = '_darcs/prefs/darcspublish'
    statefile = '_darcs/darcspublish-state'
  when 'git'
    configfile = '.git/darcspublish'
    statefile = '.git/darcspublish-state'
  when 'plain'
    configfile = Dir.pwd + '/_darcspublish'
    statefile = Dir.pwd + '/_darcspublish-state'
  else
    $stderr.puts "Unsupported repository type: #{$type}."
    exit 1
  end
  config = {}
  files = [ ENV['HOME'] + '/.darcspublish' ]
  files.push configfile
  if profile then files.push configfile + '.' + profile end
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
  
  if !config.has_key? 'UPLOAD' then config['UPLOAD'] = 'BOTH' end
  if !config.has_key? 'EXCLUDE' then config['EXCLUDE'] = '' end
  if !config.has_key? 'BASEDIR' then config['BASEDIR'] = '' end

  if !config.has_key? 'SERVER' or
     !config.has_key? 'USER' or !config.has_key? 'PASSWORD' then
    $stderr.puts "Configuration incomplete."
    exit 1
  end

  config['TYPE'] = type
  config['STATEFILE'] = statefile
  config['CONFIGFILE'] = configfile
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
  cfg = loadProfile
  cfg['PROJECT'] = File.basename(Dir.pwd)

  if cfg.has_key?('DIR') then
    cfg['REMOTEDIR'] = cfg['DIR']
  else
    cfg['REMOTEDIR'] = cfg['BASEDIR'] + '/' + cfg['PROJECT']
  end

  $tempDir = createTempDir
  
  print "*** Creating clean working copy: "
  $stdout.flush
  
  case cfg['TYPE']
  when 'darcs'
    if cfg['UPLOAD'] == 'CONTENT' and File.directory? '_darcs/pristine' then
      cfg['SOURCEDIR'] = Dir.pwd + '/_darcs/pristine'
    else
      exit 1 unless system "darcs put #{$tempDir}/repocopy >/dev/null"
      cfg['SOURCEDIR'] = $tempDir + '/repocopy'
      if cfg['UPLOAD'] == 'CONTENT' then
        cfg['EXCLUDE'] += ' _darcs'
      else
        cfg['SOURCEDIR'] == $tempDir + '/repocopy/_darcs'
		cfg['EXCLUDE'] += ' _darcs/pristine' if cfg['UPLOAD'] == 'REPO' 
      end
    end
  when 'git'
    bare = cfg['UPLOAD'] == 'REPO' ? ' --bare' : '';
    exit 1 unless system "git clone#{bare} . #{$tempDir}/repocopy >/dev/null"
    exit 1 unless system "cd #{$tempDir}/repocopy && rm -rf .git/logs .git/index && git update-server-info >/dev/null && cd #{Dir.pwd}"
    cfg['SOURCEDIR'] = $tempDir + '/repocopy'
    if cfg['UPLOAD'] == 'CONTENT' then
      cfg['EXCLUDE'] += ' /.git'
    #elsif cfg['UPLOAD'] == 'REPO' then
    #  cfg['SOURCEDIR'] = $tempDir + '/repocopy/.git'
    end
  else
    cfg['SOURCEDIR'] = Dir.pwd
    cfg['EXCLUDE'] += ' ' + File.basename(cfg['CONFIGFILE']) + ' ' + File.basename(cfg['STATEFILE'])
  end
  
  #if !cfg.has_key? 'PRISTINE' or 
  #   (cfg.has_key? 'PRISTINE' and !File.directory? '_darcs/pristine') then
    
    # hier soll abhängig vom type und pristine=yes/no
    # das cfg['SOURCEDIR'] gesetzt werden
  #  print "*** Creating clean working copy: "
  #  if File.readable? '_darcs/prefs/defaultrepo' then
  #    FileUtils.cp '_darcs/prefs/defaultrepo', "#{$tempDir}/defaultrepo"
#    end

 #   exit 1 unless system 'darcs put ' + (cfg['EXCLUDEPRISTINE'].empty? ? '' : '--no-pristine-tree ') + $tempDir + '/darcscopy >/dev/null'
    puts "ok"

  if cfg.has_key? 'TEMPLATES' and
     (cfg['UPLOAD'] == 'CONTENT' or cfg['UPLOAD'] == 'BOTH') then
    puts "*** Excludes: #{cfg['EXCLUDE']}"
    print "*** Processing templates (#{cfg['TEMPLATES']}): "
    $stdout.flush
    
    publishTime = Time.now
    Dir.mkdir($tempDir + '/repoclone')
    Dir.glob(cfg['SOURCEDIR']+'/**/*', File::FNM_DOTMATCH) do |f|
      next if File.basename(f) == '.' or File.basename(f) == '..'
      name = f.slice(cfg['SOURCEDIR'].length, f.length - cfg['SOURCEDIR'].length)
      
	  excluded = false
	  cfg['EXCLUDE'].strip.split(/\s+/).each do |i|
	  	next unless (i[0,1] == '/' and File.fnmatch?(i, name)) or
	  	            File.fnmatch?(i, File.basename(name))
	  	excluded = true
	  	break
	  end unless !cfg.has_key? 'EXCLUDE'
      next if excluded

      if File.directory? f then
        FileUtils.mkdir_p($tempDir + '/repoclone' + name, :mode => File.lstat(f).mode)
      else
        if File.symlink? f then
          File.symlink(File.readlink(f), $tempDir + '/repoclone' + name)
	      File.lchmod(File.lstat(f).mode, $tempDir + '/repoclone' + name)
        else
          begin
    		File.link(f, $tempDir + '/repoclone' + name)
  	      rescue
  		    FileUtils.cp(f, $tempDir + '/repoclone' + name)
	        File.chmod(File.stat(f).mode, $tempDir + '/repoclone' + name)
  		  end
  		end
  		
	    matches = false
	    cfg['TEMPLATES'].strip.split(/\s+/).each do |i|
	    	next unless (i[0,1] == '/' and File.fnmatch?(i, name)) or
	    	            File.fnmatch?(i, File.basename(name))
	    	matches = true
	    	break
	    end
        next if not matches

		# do replacement in file $tempDir+'/repoclone' + name
		context = TemplateInformation.new(name,
		                                  find_mtime(cfg['TYPE'], Dir.pwd, name),
		                                  publishTime)
		template = File.read($tempDir + '/repoclone' + name)
		output = ERB.new(template).result(context.get_binding)
		
		# don't use the original file, as it may be hardlinked!
		File.unlink($tempDir+'/repoclone'+name)
		
		File.open($tempDir+'/repoclone'+name,
		          File::WRONLY|File::CREAT|File::TRUNC, File.stat(f).mode) do |o|
			o.write(output)
		end
		print "."
		$stdout.flush
      end
    end
    puts " ok"
    cfg['SOURCEDIR'] = $tempDir+'/repoclone'
   end
   #exit 1


  #  if File.readable? '_darcs/prefs/email' then
  #    FileUtils.cp "_darcs/prefs/email", "#{$tempDir}/darcscopy/_darcs/prefs"
  #  end
  #  if File.readable? "#{$tempDir}/defaultrepo" then
  #    FileUtils.cp "#{$tempDir}/defaultrepo", "_darcs/prefs/"
  #  end

    # if we're simulating PRISTINE, we need to EXCLUDE _darcs
  #  cfg['EXCLUDE'] = '_darcs ' + (cfg.has_key?('EXCLUDE') ? cfg['EXCLUDE'] : '')
    # if someone asks, say NO, as we're only simulating it :)
  #  cfg.delete 'PRISTINE'
  #end

  FileUtils.touch $tempDir + '/rc'
  FileUtils.chmod 0600, $tempDir + '/rc'
  rc = File.new($tempDir + '/rc', 'w')
  rc.puts 'site darcspublish',
          '  server ' + cfg['SERVER'],
          '  username ' + cfg['USER'],
          '  password ' + cfg['PASSWORD'],
          '  remote ' + cfg['REMOTEDIR'],
          '  local ' + cfg['SOURCEDIR'],
          '  protocol ftp',
          '  state checksum',
          '  permissions all',
          '  symlinks ignore'
  cfg['EXCLUDE'].strip.split(/\s+/).each do |i|
    rc.puts "  exclude #{i}"
  end unless !cfg.has_key? 'EXCLUDE'
  rc.close
  
  FileUtils.mkdir $tempDir + '/state'
  FileUtils.chmod 0700, $tempDir + '/state'
  if File.exists? cfg['STATEFILE'] then
    FileUtils.cp cfg['STATEFILE'], $tempDir + '/state/darcspublish'
  end
  if cfg.has_key? 'UPLOADSTATE' then
    print "*** Attempting to download state file: "
    Net::FTP.open(cfg['SERVER'], cfg['USER'], cfg['PASSWORD']) do |ftp|
      ftp.passive = true
      begin
        ftp.getbinaryfile "#{cfg['REMOTEDIR']}/.darcspublishstate",
                          "#{$tempDir}/state/darcspublish"
        puts "ok"
        #FileUtils.mv "#{$tempDir}/statefile", "_darcs/sitecopystate/darcspublish"
      rescue
        puts "not found"
        FileUtils.rm_rf "#{$tempDir}/state/darcspublish"
      end
    end
  end

  if !File.exists? $tempDir + '/state/darcspublish' then
    puts "*** Publishing from here for the first time."
    print "*** Creating directory on remote server: "
    Net::FTP.open(cfg['SERVER'], cfg['USER'], cfg['PASSWORD']) do |ftp|
      ftp.passive = true
      begin
        ftp.mkdir "#{cfg['REMOTEDIR']}"
        puts "ok"
      rescue
        puts "error. exists? whatever..."
      end
    end
    print "*** Setting up initial state: "
    exit 1 unless system "sitecopy -r #{$tempDir}/rc -p #{$tempDir}/state -i darcspublish"
    exit 1 unless system "sitecopy -r #{$tempDir}/rc -p #{$tempDir}/state -f darcspublish"
    puts "ok"
  else
    puts "*** Found state file."
  end

  if cfg.has_key? 'CAREFUL' then
    puts "*** I'm being careful."
    system "sitecopy -r #{$tempDir}/rc -p #{$tempDir}/state -l darcspublish"
    print "*** PRESS CTRL-C TO CANCEL OR RETURN TO CONTINUE!"
    $stdin.getc
  end
  
  # do the actual update
  exit 1 unless system "sitecopy -r #{$tempDir}/rc -p #{$tempDir}/state -u darcspublish"

  if cfg.has_key? 'UPLOADSTATE' then
    print "*** Uploading state file: "
    Net::FTP.open(cfg['SERVER'], cfg['USER'], cfg['PASSWORD']) do |ftp|
      ftp.passive = true
      begin
        ftp.putbinaryfile $tempDir + '/state/darcspublish',
                          "#{cfg['REMOTEDIR']}/.darcspublishstate"
        puts "ok"
      rescue
        puts "error"
      end
    end
  end
  
  FileUtils.cp $tempDir + '/state/darcspublish', cfg['STATEFILE']
  
  #puts "*** CONFIGURATION USED ***"
  #cfg.each_pair do |k, v|
  #  puts "#{k}: #{v}"
  #end
end

main
