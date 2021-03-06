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
    begin
      require 'blinkstick'
      @led_queue = Queue.new
      led_thread
      led("ended")
      @@led = true
      puts "led support enabled"
    rescue
      @@led = false
      puts "led support disabled"
    end
    start_running
  end

  def led(state="error", ber=0)
    begin
      return unless @@led
      @led_queue.push({state: state, ber: ber})
      return true
    rescue => e
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
    end
  end

  def led_thread
    begin
      Thread.new do
        @last_set = Time.now.to_f
        while action = @led_queue.pop do
          if action[:state] == "ended"
            BlinkStick.find_all.each { |b|
              b.set_color(0, 0, Color::RGB.new(0,0,0))
              b.set_color(0, 1, Color::RGB.new(0,0,0))
              @last_color = "0"
            }
          elsif action[:state] == "rx"
            BlinkStick.find_all.each { |b|
              #puts "ber is #{action[:ber]}"
              #brightness is set based on ber * 5 to make it obvious
              color = 255 * (1 - action[:ber] * 5)
              if color < 1
                color = 1
              end
              #puts "color is #{color}"
              if @last_color != color
                #puts "new color"
                if Time.now.to_f - @last_set > 0.5
                  #puts "past timeout"
                  b.set_color(0, 0, Color::RGB.new(0,color,0))
                  b.set_color(0, 1, Color::RGB.new(0,color,0))
                  @last_set = Time.now.to_f
                  @last_color = color
                end
              end
            }
          elsif action[:state] == "tx"
            BlinkStick.find_all.each { |b|
              b.set_color(0, 0, Color::RGB.new(255,0,0))
              b.set_color(0, 1, Color::RGB.new(255,0,0))
              @last_color = "256"
            }
          elsif action[:state] == "int"
            BlinkStick.find_all.each { |b|
              b.set_color(0, 0, Color::RGB.new(178,0,255))
              b.set_color(0, 1, Color::RGB.new(178,0,255))
              @last_color = "256"
            }
          else
            BlinkStick.find_all.each { |b|
              b.set_color(0, 0, Color::RGB.new(255,255,255))
              b.set_color(0, 1, Color::RGB.new(255,255,255))
              @last_color = "256"
            }
          end
          sleep 0.05
        end
      end
    rescue => e
      @@led_thread = false
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
    end
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
          column = "left"
          @most_recent.sort.each do |k,v|
            if k == @currently_speaking.split(' ')[0]
              pbuff << "\e[1m"
            end
            if column == "left"
              pbuff << "#{k}: #{v}".ljust(75)
            else
              pbuff << "#{k}: #{v}"
            end
            if k == @currently_speaking.split(' ')[0]
              pbuff << "\e[22m"
            end
            if column == "left"
              column = "right"
            else
              pbuff << "\n"
              column = "left"
            end
          end
          puts pbuff
          sleep 1
        end
      end
    rescue => e
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
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
      @@logger.debug(e.backtrace)
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
        #PTY.spawn("#{MD380TOOLS}md380-tool dmesgtail") do |stdout, stdin, pid|
        PTY.spawn("ssh root@192.168.1.232 'tail -q -n0 -f /var/log/MMDVM-*.log'") do |stdout, stdin, pid|
          stdin.close
          stdout.each do |line|
            line.chomp!
            next if line.empty?
            next unless line[0..1] == '[* ]' || line[0..1] == 'M:' || line[0..1] == 'D:'
            received_time = Time.now.to_f
            message = parse_line("#{received_time} #{line.strip}")
            next if message == "audio"
            self.radio_queue << message
          end
        end
      end
    rescue
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
      exit 1
    ensure
      @loggie.close if @loggie
    end
  end

#mmdvm
#rx
#M: 2019-09-06 18:43:57.822 DMR Slot 2, received RF voice header from 47 to TG 1
#M: 2019-09-06 18:43:58.003 DMR Slot 2, received RF end of voice transmission, 0.0 seconds, BER: 0.0%
#tx
#M: 2019-03-08 04:26:37.720 DMR Slot 2, received network voice header from 3127787 to TG 98638
#M: 2019-03-08 04:26:47.266 DMR Slot 2, received network end of voice transmission from 3127787 to TG 98638, 9.5 seconds, 0% packet loss, BER: 0.0%
#RF Quality
#D: 2019-03-08 04:41:08.546 DMR Slot 2, audio sequence no. 5, errs: 0/141 (0.0%)

#dmesgtail
#1507594330 * Call from 3133002 to group 3181 started.
#1507594351 * Call from 3133002 to group 3181 ended.
  def parse_line(line)
    begin
      @loggie.write("#{line}\n")
      line = line.split(" ")
      if line[9] == 'voice'
        return Message.new(line[12],line[15],'started.',line[0].to_f,GROUP,line[8])
      elsif line[9] == 'end'
        return Message.new(line[14],line[17].gsub(',',''),'ended.',line[0].to_f,GROUP,line[8])
      elsif line[7] == "audio"
        led("rx", line[-2].split('/')[0].to_i / 141.0)
        return "audio"
      elsif line[6] == 'group'
        return Message.new(line[4],line[7],line.last,line[0].to_f,GROUP,"RF")
      elsif line =~ /Call from/
        return Message.new(line[4],line[6],line.last,line[0].to_f,PRIV,"RF")
      end
    rescue => e
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
      exit 1
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
            process_call(message) unless message.nil?
          end
        end
      end
    rescue => e
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
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
      led("ended")
    rescue => e
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
      exit 1
    end
  end

  def start_new_call(message)
    begin
      puts "tx started     : #{message.caller_id} #{message.user} to #{message.call_type} #{message.receiver_id} #{message.tg}"
      self.current_call = message
      @currently_speaking = "#{message.caller_id} #{message.user}"
      @most_recent[message.caller_id] = "#{message.user} #{Time.at(message.received_time).to_s}"
      if message.source == "RF"
        led("rx")
      elsif message.source == "network"
        led("tx")
      else
        led
      end
    rescue => e
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
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
      led("int")
    rescue => e
      @@logger.debug(e.inspect)
      @@logger.debug(e.backtrace)
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
      @@logger.debug(e.backtrace)
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
      @@logger.debug(e.backtrace)
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
      @@logger.debug(e.backtrace)
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
  attr_accessor :source
  MD380TOOLS = "/home/zero/development/md380tools/".freeze
  #headers = "Radio ID,Callsign,Name,City,State,Country,Remarks".freeze
  @@db =  nil
  @@db_last = 0

  def initialize(c_id,r_id,message_type,time,type,source="RF")
    begin
      self.class.users
      self.caller_id = c_id
      self.receiver_id = r_id
      self.state = message_type
      self.received_time = time
      self.call_type = type
      self.source = source
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end

  def user
    begin
      user = @@db[self.caller_id]
      if user.nil? || user.empty?
        if (Time.now.to_i - @@db_last) > 60
          puts @@db_last
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
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end

  def tg
    begin
      if self.receiver_id == '1'
        tg = 'Derbycon'
      elsif self.receiver_id == '98638'
        tg = 'WVNet'
      else
        tg = 'the wrong talkgroup, so no one heard it'
      end

      return tg
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end

  def self.users(override=false)
    begin
      if (Time.now.to_i - @@db_last) > 600 || override
        #self.update_db
        #csv_file = CSV.parse("Radio ID,Callsign,Name,City,State,Country,Remarks\n#{File.read("#{MD380TOOLS}/db/stripped.csv").gsub('"', "'")}", {:headers => true, :header_converters => :symbol})
        #csv_file = CSV.parse("Name,Callsign,Radio ID,City\n#{File.read("#{MD380TOOLS}/db/stripped.csv").gsub('"', "'")}", {:headers => true, :header_converters => :symbol})
        hashie = Hash.new
        #csv_file.map(&:to_hash).each{|row| hashie[row.delete(:radio_id)] = row }
        #x = File.read '/tmp/custom.csv'
        #hashie = Hash[x.split("\n").map{|y| y.split(',')[0,2] }] 
        x = File.read 'DMRIds.dat'
        hashie = Hash[x.split("\n").map{|y| y.split("\t")[0,2] }].invert
        @@db = hashie
        @@db_last = Time.now.to_i
        puts "#{:user_list}"
        puts "#{@@db}"
      end
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end

  def time_diff(current_time)
    begin
      return (self.received_time - current_time).round(2)
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end

  def to_s
    begin
      [
        @@id_lookup[self.caller_id],
        "-->",
        self.receiver_id
      ].join(' ')
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end
 
  def self.update_derby_db
    begin
      puts "updating db"
      #`curl 'https://docs.google.com/spreadsheets/d/1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4/export?format=csv&id=1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4&gid=0' > /tmp/custom.csv`
      #`curl 'https://docs.google.com/spreadsheets/d/1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4/export?format=csv&id=1ph5Wh0Wztljtdd5PLKGipwEuYE3LIHT-1wSOs-e6iV4&gid=1919271561' > /tmp/custom1.csv`
      `curl 'https://docs.google.com/spreadsheets/d/1bAIPm1okjKVg3mhWBd2lGjKGp9sMpVsN_Tc0yDzda-c/export?format=csv' > /tmp/custom1.csv`
      `sed -i '1d' /tmp/custom1.csv`
      `dos2unix /tmp/custom1.csv > /dev/null 2>&1`
      `awk -F',' '{print $3","$2}' /tmp/custom1.csv > /tmp/custom2.csv`
      `[ -n "$(cat /tmp/custom2.csv)" ] && mv /tmp/custom2.csv /tmp/custom.csv`
      puts "#{:db_done}"
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end

  def self.update_db
    begin
      puts "#{:updating_db}"
      #`cd #{MD380TOOLS}; make updatedb`
      puts "#{:intentionally_nerfed}"
      #update_derby_db
      puts "#{:updated}"
    rescue => e
      puts e.inspect
      puts e.backtrace
      exit 1
    end
  end

  #this is just to show it all worked
  users

end

Dmrrr.new
while true
sleep 10
end
