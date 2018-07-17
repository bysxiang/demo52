require 'date'
require 'rational' unless defined?(Rational)
require 'time'

module TZInfo
  # Used by TZInfo internally to represent either a Time, DateTime or
  # an Integer timestamp (seconds since 1970-01-01 00:00:00).
  #
  # 在TZInfo内部用于表示Time、DateTime或时间戳的对象
  class TimeOrDateTime
    include Comparable
    
    # Constructs a new TimeOrDateTime. timeOrDateTime can be a Time, DateTime
    # or Integer. If using a Time or DateTime, any time zone information 
    # is ignored.
    #
    # Integer timestamps must be within the range supported by Time on the
    # platform being used.
    #
    # 构造一个新的TimeOrDateTime对象。timeOrDateTime可以是Time、DateTime或数字
    #。如果提供了一个Time或DateTime，所有的时区信息将被忽略 
    #
    # 
    def initialize(timeOrDateTime)
      # 这3个实例变量标识了此对象时如何被构造的
      # 如果是传入的Time，则会初始化@time，依次类推
      @time = nil
      @datetime = nil
      @timestamp = nil

      #@orig 表示的对象，它表示最终构造的时间对象，
      # 例如@time, @datetime, @timestamp
      
      if timeOrDateTime.is_a?(Time)
        @time = timeOrDateTime
        
        # Avoid using the slower Rational class unless necessary.
        nsec = RubyCoreSupport.time_nsec(@time)
        usec = nsec % 1000 == 0 ? nsec / 1000 : Rational(nsec, 1000)
        
        @time = Time.utc(@time.year, @time.mon, @time.mday, @time.hour, @time.min, @time.sec, usec) unless @time.utc?        
        @orig = @time
      elsif timeOrDateTime.is_a?(DateTime)
        @datetime = timeOrDateTime
        @datetime = @datetime.new_offset(0) unless @datetime.offset == 0
        @orig = @datetime
      else
        @timestamp = timeOrDateTime.to_i
        
        if !RubyCoreSupport.time_supports_64bit && (@timestamp > 2147483647 || @timestamp < -2147483648 || (@timestamp < 0 && !RubyCoreSupport.time_supports_negative))
          raise RangeError, 'Timestamp is outside the supported range of Time on this platform'
        end
        
        @orig = @timestamp
      end
    end
    
    # Returns the time as a Time.
    #
    # When converting from a DateTime, the result is truncated to microsecond
    # precision.
    #
    # 返回一个Time对象，如果不是Time构造的实例，转换为微秒精度
    def to_time
      # Thread-safety: It is possible that the value of @time may be 
      # calculated multiple times in concurrently executing threads. It is not 
      # worth the overhead of locking to ensure that @time is only 
      # calculated once.
    
      if ! @time
        if @timestamp
          result = Time.at(@timestamp).utc
        else
          result = Time.utc(year, mon, mday, hour, min, sec, usec)
        end

        if frozen?
          return result
        end

        @time = result
      end
      
      @time      
    end
    
    # Returns the time as a DateTime.
    #
    # When converting from a Time, the result is truncated to microsecond
    # precision.
    #
    # 返回一个DateTime对象，当发生转换得到时，截断为微妙
    def to_datetime
      # Thread-safety: It is possible that the value of @datetime may be 
      # calculated multiple times in concurrently executing threads. It is not 
      # worth the overhead of locking to ensure that @datetime is only 
      # calculated once.
    
      if ! @datetime
        # Avoid using Rational unless necessary.
        u = usec
        s = u == 0 ? sec : Rational(sec * 1000000 + u, 1000000)
        result = RubyCoreSupport.datetime_new(year, mon, mday, hour, min, s)
        if frozen?
          return result
        end
        @datetime = result
      end
      
      @datetime
    end
    
    # Returns the time as an integer timestamp.
    def to_i
      # Thread-safety: It is possible that the value of @timestamp may be 
      # calculated multiple times in concurrently executing threads. It is not 
      # worth the overhead of locking to ensure that @timestamp is only 
      # calculated once.
    
      unless @timestamp
        result = to_time.to_i
        return result if frozen?
        @timestamp = result
      end
      
      @timestamp
    end
    
    # Returns the time as the original time passed to new.
    def to_orig
      @orig
    end
    
    # Returns a string representation of the TimeOrDateTime.
    def to_s
      if @orig.is_a?(Time)
        "Time: #{@orig.to_s}"
      elsif @orig.is_a?(DateTime)
        "DateTime: #{@orig.to_s}"
      else
        "Timestamp: #{@orig.to_s}"
      end
    end
    
    # Returns internal object state as a programmer-readable string.
    def inspect
      "#<#{self.class}: #{@orig.inspect}>"
    end
    
    # Returns the year.
    def year
      if @time
        @time.year
      elsif @datetime
        @datetime.year
      else
        to_time.year
      end
    end
    
    # Returns the month of the year (1..12).
    def mon
      if @time
        @time.mon
      elsif @datetime
        @datetime.mon
      else
        to_time.mon
      end
    end
    alias :month :mon
    
    # Returns the day of the month (1..n).
    def mday
      if @time
        @time.mday
      elsif @datetime
        @datetime.mday
      else
        to_time.mday
      end
    end
    alias :day :mday
    
    # Returns the hour of the day (0..23).
    def hour
      if @time
        @time.hour
      elsif @datetime
        @datetime.hour
      else
        to_time.hour
      end
    end
    
    # Returns the minute of the hour (0..59).
    def min
      if @time
        @time.min
      elsif @datetime
        @datetime.min
      else
        to_time.min
      end
    end
    
    # Returns the second of the minute (0..60). (60 for a leap second).
    def sec
      if @time
        @time.sec
      elsif @datetime
        @datetime.sec
      else
        to_time.sec
      end
    end
    
    # Returns the number of microseconds for the time.
    def usec      
      if @time
        @time.usec
      elsif @datetime
        # Ruby 1.8 has sec_fraction (of which the documentation says
        # 'I do NOT recommend you to use this method'). sec_fraction no longer
        # exists in Ruby 1.9.
        
        # Calculate the sec_fraction from the day_fraction.
        ((@datetime.day_fraction - OffsetRationals.rational_for_offset(@datetime.hour * 3600 + @datetime.min * 60 + @datetime.sec)) * 86400000000).to_i
      else 
        0
      end
    end
    
    # Compares this TimeOrDateTime with another Time, DateTime, timestamp 
    # (Integer) or TimeOrDateTime. Returns -1, 0 or +1 depending 
    # whether the receiver is less than, equal to, or greater than 
    # timeOrDateTime.
    #
    # Returns nil if the passed in timeOrDateTime is not comparable with 
    # TimeOrDateTime instances.
    #
    # Comparisons involving a DateTime will be performed using DateTime#<=>.
    # Comparisons that don't involve a DateTime, but include a Time will be
    # performed with Time#<=>. Otherwise comparisons will be performed with
    # Integer#<=>.    
    def <=>(timeOrDateTime)
      return nil unless timeOrDateTime.is_a?(TimeOrDateTime) || 
                        timeOrDateTime.is_a?(Time) ||
                        timeOrDateTime.is_a?(DateTime) ||
                        timeOrDateTime.respond_to?(:to_i)
    
      unless timeOrDateTime.is_a?(TimeOrDateTime)
        timeOrDateTime = TimeOrDateTime.wrap(timeOrDateTime)
      end
          
      orig = timeOrDateTime.to_orig
      
      if @orig.is_a?(DateTime) || orig.is_a?(DateTime)
        # If either is a DateTime, assume it is there for a reason 
        # (i.e. for its larger range of acceptable values on 32-bit systems).
        to_datetime <=> timeOrDateTime.to_datetime
      elsif @orig.is_a?(Time) || orig.is_a?(Time)
        to_time <=> timeOrDateTime.to_time
      else
        to_i <=> timeOrDateTime.to_i
      end
    end
    
    # Adds a number of seconds to the TimeOrDateTime. Returns a new 
    # TimeOrDateTime, preserving what the original constructed type was.
    # If the original type is a Time and the resulting calculation goes out of
    # range for Times, then an exception will be raised by the Time class.
    def +(seconds)
      if seconds == 0
        self
      else
        if @orig.is_a?(DateTime)
          TimeOrDateTime.new(@orig + OffsetRationals.rational_for_offset(seconds))
        else
          # + defined for Time and Integer
          TimeOrDateTime.new(@orig + seconds)
        end
      end
    end
    
    # Subtracts a number of seconds from the TimeOrDateTime. Returns a new 
    # TimeOrDateTime, preserving what the original constructed type was.
    # If the original type is a Time and the resulting calculation goes out of
    # range for Times, then an exception will be raised by the Time class.
    def -(seconds)
      self + (-seconds)
    end
   
    # Similar to the + operator, but converts to a DateTime based TimeOrDateTime
    # where the  Time or Integer timestamp to go out of the allowed range for a 
    # Time, converts to a DateTime based TimeOrDateTime.
    #
    # Note that the range of Time varies based on the platform.
    def add_with_convert(seconds)
      if seconds == 0
        self
      else
        if @orig.is_a?(DateTime)
          TimeOrDateTime.new(@orig + OffsetRationals.rational_for_offset(seconds))
        else
          # A Time or timestamp.
          result = to_i + seconds
          
          if ((result > 2147483647 || result < -2147483648) && !RubyCoreSupport.time_supports_64bit) || (result < 0 && !RubyCoreSupport.time_supports_negative)
            result = TimeOrDateTime.new(to_datetime + OffsetRationals.rational_for_offset(seconds))
          else
            result = TimeOrDateTime.new(@orig + seconds)
          end
        end
      end
    end
    
    # Returns true if todt represents the same time and was originally 
    # constructed with the same type (DateTime, Time or timestamp) as this 
    # TimeOrDateTime.
    def eql?(todt)
      todt.kind_of?(TimeOrDateTime) && to_orig.eql?(todt.to_orig)      
    end
    
    # Returns a hash of this TimeOrDateTime.
    def hash
      @orig.hash
    end
    
    # 如果没有提供一个块，则返回包装给定的TimeOrDateTime实例。如果指定了块，则构造TimeOrDateTime并传递给
    # 块，这个块必须返回TimeOrDateTime类型
    #
    # 结果将转换为原始类型。
    #
    # 参数timeOrDateTime可以是TimeOrDateTime、Time、DateTime或时间戳。如果传入的是TimeOrDateTime，不会构造新的
    # 对象，否则将构造一个新的，并根据传入的类型，最终返回原类型
    #
    # 备注：那么这个方法的行为就很清晰了，它去除时区信息，如果是Time、DateTime，将被表示成UTC时间(即不考虑它的时区)
    def self.wrap(timeOrDateTime)
      t = timeOrDateTime.is_a?(TimeOrDateTime) ? timeOrDateTime : TimeOrDateTime.new(timeOrDateTime)
      
      if block_given?
        t = yield t
        
        if timeOrDateTime.is_a?(TimeOrDateTime)
          t
        elsif timeOrDateTime.is_a?(Time)
          t.to_time
        elsif timeOrDateTime.is_a?(DateTime)
          t.to_datetime
        else
          t.to_i
        end        
      else
        t
      end
    end # self.wrap .. end


  end
end
