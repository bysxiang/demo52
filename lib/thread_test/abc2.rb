
module ThreadTest
  class Abc2
    thread_mattr_reader :user
    thread_mattr_writer :user
  end

  class Ddd < Abc2

  end
end

p ThreadTest::Abc2.user
ThreadTest::Abc2.user = "hh"
p ThreadTest::Abc2.user
p ThreadTest::Abc2.new.user
p ThreadTest::Ddd.user
p ThreadTest::Ddd.new.user