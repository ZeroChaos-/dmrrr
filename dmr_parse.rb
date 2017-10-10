#!/usr/bin/env ruby
require 'pry'
require 'pty'

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
    start_running
  end

  def start_running
    parser_thread
    read_thread
    twitter_thread
  end

  def twitter_thread
    begin
      Thread.new do
        while msg = @twitter_queue.pop do
          #puts "Tweeting: .#{msg[0..158]}"
          #`./twitbot.py -m "#{msg[0..158]}" 2>&1 | grep 'tweepy.error.TweepError'`
          sleep 3
        end
      end
    rescue => e
      binding.pry
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
    require 'pry'
    binding.pry
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
    rescue
    binding.pry
    end
  end

  def complete_call(message)
    puts "tx completed   : #{message.caller_id} #{message.user} to #{message.call_type} #{message.receiver_id} #{message.tg}, duration: #{message.time_diff(self.current_call.received_time)}s"
    @twitter_queue.push "#{Time.at(self.current_call.received_time).to_s} - #{message.user} transmitted to #{message.call_type} #{message.tg}, duration: #{message.time_diff(self.current_call.received_time)}s #derbycon" unless message.time_diff(self.current_call.received_time) < 1
    self.current_call = nil
  end

  def start_new_call(message)
    puts "tx started     : #{message.caller_id} #{message.user} to #{message.call_type} #{message.receiver_id} #{message.tg}"
    self.current_call = message
  end

  def call_inturrupted(message)
    puts "tx interrupted : #{message.caller_id} #{message.user} interrupted #{self.current_call.caller_id} #{self.current_call.user} like a real asshole, duration: #{message.time_diff(self.current_call.received_time)}s"
    @twitter_queue.push "#{Time.at(self.current_call.received_time).to_s} - #{message.user} interrupted #{self.current_call.user} like a jerk, duration: #{message.time_diff(self.current_call.received_time)}s #derbycon" unless message.time_diff(self.current_call.received_time) < 1
    self.current_call = message
  end

  def same_id_message(message)
    if self.current_call.state == STARTED
      if message.state == ENDED
        complete_call(message)
      end
    else
      start_new_call(message)
    end
  end

  def different_id_message(message)
    if self.current_call.state == ENDED
      start_new_call(message)
    else
      call_inturrupted(message)
    end
  end

  def process_call(message)
  if self.current_call.nil?
     start_new_call(message)
    elsif message.caller_id == self.current_call.caller_id
      same_id_message(message)
    else
      different_id_message(message)
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
    if user.nil?
      user = "unknown hacker"
    elsif user.empty?
      Message.users(true) unless @@last_talker.empty?
      user = @@db[self.caller_id]
      if user.empty?
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
    if (Time.now.to_i - @@db_last) > 86400 || override
      self.update_db
      csv_file = CSV.parse("Radio ID,Callsign,Name,City,State,Country,Remarks\n#{File.read("#{MD380TOOLS}/db/stripped.csv").gsub('"', "'")}", {:headers => true, :header_converters => :symbol})
      hashie = Hash.new
      csv_file.map(&:to_hash).each{|row| hashie[row.delete(:radio_id)] = row }
      #x = File.read '/tmp/custom.csv'
      #hashie = Hash[x.split("\n").map{|y| y.split(',')[0,2] }] 
      #hashie["9046"] = "Medic"
      @@db = hashie
      @@db_last = Time.now.to_i
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
  puts "updating db "
`curl 'https://docs.google.com/spreadsheets/d/1Yc0y_ar1_f04eSEQQ6FKnSO5jQeGEB2EZFzT8KvCUgo/export?format=csv&id=1Yc0y_ar1_f04eSEQQ6FKnSO5jQeGEB2EZFzT8KvCUgo&gid=0' > /tmp/custom.csv`
`sed -i '1d' /tmp/custom.csv`
`dos2unix /tmp/custom.csv > /dev/null 2>&1`
puts :db_done
  end

  def self.update_db
    puts :updating_db
    #`cd #{MD380TOOLS}; make updatedb`
    puts :intentionally_nerfed
    puts :updated
  end

  users

end

Dmrrr.new
while true
sleep 10
end
