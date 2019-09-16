#!/usr/bin/env ruby
require 'pty'
require 'logger'

class Dmrrr
  attr_accessor :radio_queue
  attr_accessor :current_call

  MD380TOOLS = "/home/zero/development/md380tools/".freeze
  STARTED = "started.".freeze
  ENDED = 'ended.'.freeze
  GROUP = 'group'.freeze
  PRIV = 'priv'.freeze

  def initialize
    self.radio_queue = []
    @twitter_queue = Queue.new
    @last_speaker = ["","","","",""]
    @most_recent = {}
    logfile = "dmrrr.log"
    @@logger = Logger.new(logfile)
    @@logger.level = Logger::DEBUG
    start_running
  end

  def start_running
    parser_thread
    read_thread
    twitter_thread
    display_thread
  end

  def display_thread
    begin
      Thread.new do
        while true
          pbuff = ""
          pbuff << "\e[H\e[2J"
          pbuff << "Currently speaking : #{@currently_speaking}\n"
          pbuff << "Last speaker       : #{@last_speaker[0]}\n"
          pbuff << "Recent speaker     : #{@last_speaker[1]}\n"
          pbuff << "Recent speaker     : #{@last_speaker[2]}\n"
          pbuff << "Recent speaker     : #{@last_speaker[3]}\n"
          pbuff << "Recent speaker     : #{@last_speaker[4]}\n"
          pbuff << "\n"
          @most_recent.sort.each do |k,v|
            if k == @currently_speaking.split(' ')[0]
              pbuff << "\e[1m#{k}: #{v}\e[22m\n"
            else
              pbuff << "#{k}: #{v}\n"
            end
          end
          puts pbuff
          sleep 1
        end
      end
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end

  def twitter_thread
    begin
      Thread.new do
        @logola = File.open("dmr_parse.twit", "a")
        @logola.sync = true
        while msg = @twitter_queue.pop do
          puts "Tweeting: .#{msg[0..158]}"
          #`./twitbot.py -m "#{msg[0..158]}" 2>&1 | grep 'tweepy.error.TweepError'`
          @logola.write("#{msg}\n")
          sleep 3
        end
      end
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    ensure
      @logola.close if @logola
    end
  end

  def parser_thread
  begin
    Thread.new do
    @loggie = File.open("dmr_parse.raw", "a")
    @loggie.sync = true
    PTY.spawn("#{MD380TOOLS}md380-tool dmesgtail") do |stdout, stdin, pid|
          stdin.close
          stdout.each do |line|
          next unless line[0..1] == '* '
          received_time = Time.now.to_f
          message = parse_line("#{received_time} #{line.strip}")
          self.radio_queue << message
        end
      end
    end
    rescue
      @@logger.debug(e.inspect)
      exit 1
    ensure
      @loggie.close if @loggie
    end
  end

  def parse_line(line)
    @loggie.write("#{line}\n")
    line = line.split(" ")
    if line[6] == 'group'
      return Message.new(line[4],line[7],line.last,line[0].to_f,GROUP)
    else
      return Message.new(line[4],line[6],line.last,line[0].to_f,PRIV)
    end
  end

  def read_thread
  begin
    Thread.new do
      loop do
        while self.radio_queue.empty? do
         sleep 1
        end
        until self.radio_queue.empty? do
         message = self.radio_queue.shift
         process_call(message)
        end
      end
    end
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end

  def complete_call(message)
    begin
    puts "tx completed   : #{message.caller_id} #{message.user} to #{message.call_type} #{message.receiver_id} #{message.tg}, duration: #{message.time_diff(self.current_call.received_time)}s"
    @twitter_queue.push "#{Time.at(self.current_call.received_time).to_s} - #{message.user} transmitted to #{message.call_type} #{message.tg}, duration: #{message.time_diff(self.current_call.received_time)}s #derbycon" unless message.time_diff(self.current_call.received_time) < 1
    self.current_call = nil
    @last_speaker.unshift "#{@currently_speaking} #{Time.at(message.received_time).to_s}"
    @last_speaker.pop
    @currently_speaking = ""
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end

  def start_new_call(message)
    begin
    puts "tx started     : #{message.caller_id} #{message.user} to #{message.call_type} #{message.receiver_id} #{message.tg}"
    self.current_call = message
    @currently_speaking = "#{message.caller_id} #{message.user}"
    @most_recent[message.caller_id] = "#{message.user} #{Time.at(message.received_time).to_s}"
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end

  def call_inturrupted(message)
    begin
    puts "tx interrupted : #{message.caller_id} #{message.user} interrupted #{self.current_call.caller_id} #{self.current_call.user} like a real asshole, duration: #{message.time_diff(self.current_call.received_time)}s"
    @twitter_queue.push "#{Time.at(self.current_call.received_time).to_s} - #{message.user} interrupted #{self.current_call.user} like a jerk, duration: #{message.time_diff(self.current_call.received_time)}s #derbycon" unless message.time_diff(self.current_call.received_time) < 1
    self.current_call = message
    @currently_speaking << ", #{message.caller_id} #{message.user}"
    @most_recent[message.caller_id] = "#{message.user} #{Time.at(message.received_time).to_s}"
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end

  def same_id_message(message)
    begin
    if self.current_call.state == STARTED
      if message.state == ENDED
        complete_call(message)
      end
    else
      start_new_call(message)
    end
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end

  def different_id_message(message)
    begin
    if self.current_call.state == ENDED
      start_new_call(message)
    else
      call_inturrupted(message)
    end
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end

  def process_call(message)
    begin
    if self.current_call.nil?
     start_new_call(message)
    elsif message.caller_id == self.current_call.caller_id
      same_id_message(message)
    else
      different_id_message(message)
    end
    rescue => e
      @@logger.debug(e.inspect)
      exit 1
    end
  end
end

class Message
  require 'csv'
  attr_accessor :caller_id
  attr_accessor :received_time
  attr_accessor :receiver_id
  attr_accessor :state
  attr_accessor :call_type
  MD380TOOLS = "/home/zero/development/md380tools/".freeze
  headers = "Radio ID,Callsign,Name,City,State,Country,Remarks".freeze
  @@db =  nil
  @@db_last = 0

  def user
    user = @@db[self.caller_id]
    if user.nil? || user.empty?
      if (Time.now.to_i - @@db_last) > 60
        Message.users(true)
      end
    end

    if user.nil?
      user = "UNALLOCATED"
    elsif user.empty?
      user = @@db[self.caller_id]
      if user.empty? || user.nil?
        user = "jerk who did not check their radio out properly"
      end
    end

    return user
  end

  def tg
    if self.receiver_id == "1"
      tg = "Derbycon"
    else
      tg = "the wrong talkgroup, so no one heard it"
    end

    return tg
  end

  def self.users(override=false)
    if (Time.now.to_i - @@db_last) > 600 || override
      self.update_db
      #csv_file = CSV.parse("Radio ID,Callsign,Name,City,State,Country,Remarks\n#{File.read("#{MD380TOOLS}/db/stripped.csv").gsub('"', "'")}", {:headers => true, :header_converters => :symbol})
      #csv_file = CSV.parse("Name,Callsign,Radio ID,City\n#{File.read("#{MD380TOOLS}/db/stripped.csv").gsub('"', "'")}", {:headers => true, :header_converters => :symbol})
      hashie = Hash.new
      #csv_file.map(&:to_hash).each{|row| hashie[row.delete(:radio_id)] = row }
      x = File.read '/tmp/custom.csv'
      hashie = Hash[x.split("\n").map{|y| y.split(',')[0,2] }] 
      #hashie["9046"] = "Medic"
      @@db = hashie
      @@db_last = Time.now.to_i
      puts "#{:user_list}"
      puts "#{@@db}"
    end
  end

  def initialize(c_id,r_id,message_type,time,type)
    self.class.users
    self.caller_id = c_id
    self.receiver_id = r_id
    self.state = message_type
    self.received_time = time
    self.call_type = type
  end


  def time_diff(current_time)
    return (self.received_time - current_time).round(2)
  end

  def to_s
  [
  @@id_lookup[self.caller_id],
  "-->",
  self.receiver_id
  ].join(' ')
  end
 
  def self.update_derby_db
    puts "updating db"
    #`curl 'https://docs.google.com/spreadsheets/d/1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4/export?format=csv&id=1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4&gid=0' > /tmp/custom.csv`
    `curl 'https://docs.google.com/spreadsheets/d/1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4/export?format=csv&id=1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4&gid=1919271561' > /tmp/custom1.csv`
    `sed -i '1d' /tmp/custom1.csv`
    `dos2unix /tmp/custom1.csv > /dev/null 2>&1`
    `awk -F',' '{print $3","$2}' /tmp/custom1.csv > /tmp/custom2.csv`
    `[ -n "$(cat /tmp/custom2.csv)" ] && mv /tmp/custom2.csv /tmp/custom.csv`
    puts "#{:db_done}"
  end

  def self.update_db
    puts "#{:updating_db}"
    #`cd #{MD380TOOLS}; make updatedb`
    puts "#{:intentionally_nerfed}"
    update_derby_db
    puts "#{:updated}"
  end

  users

end

Dmrrr.new
while true
sleep 10
end
