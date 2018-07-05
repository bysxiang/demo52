# frozen_string_literal: true

module DateAndTime
  module Zones
    # Returns the simultaneous time in <tt>Time.zone</tt> if a zone is given or
    # if Time.zone_default is set. Otherwise, it returns the current time.
    #
    #   Time.zone = 'Hawaii'        # => 'Hawaii'
    #   Time.utc(2000).in_time_zone # => Fri, 31 Dec 1999 14:00:00 HST -10:00
    #   Date.new(2000).in_time_zone # => Sat, 01 Jan 2000 00:00:00 HST -10:00
    #
    # This method is similar to Time#localtime, except that it uses <tt>Time.zone</tt> as the local zone
    # instead of the operating system's time zone.
    #
    # You can also pass in a TimeZone instance or string that identifies a TimeZone as an argument,
    # and the conversion will be based on that zone instead of <tt>Time.zone</tt>.
    #
    #   Time.utc(2000).in_time_zone('Alaska') # => Fri, 31 Dec 1999 15:00:00 AKST -09:00
    #   Date.new(2000).in_time_zone('Alaska') # => Sat, 01 Jan 2000 00:00:00 AKST -09:00
    # 
    # 将时间转换为对应时区的时间, 如果对应时区存在，则转换
    # 否则返回时间对象(DateTime或Time)
    def in_time_zone(zone = ::Time.zone)
      time_zone = ::Time.find_zone! zone
      time = acts_like?(:time) ? self : nil

      if time_zone
        time_with_zone(time, time_zone)
      else 
        # 当zone为nil或false时，返回time或to_time(即当前时间)
        time || to_time
      end
    end

    private

      # time 可能是一个Time类也可能是nil
      def time_with_zone(time, zone)
        if time
          utc_time = time.utc? ? time : time.getutc
          ActiveSupport::TimeWithZone.new(utc_time, zone)
        else
          # 当前对象为Date时
          utc_time = to_time(:utc)
          ActiveSupport::TimeWithZone.new(nil, zone, utc_time)
        end
      end
  end
end
