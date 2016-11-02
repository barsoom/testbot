require 'rubygems'
require 'net/ssh'

class SSHTunnel
  # We want a small number so this fails quickly when unreachable. But not too small: a lower value caused false negatives on a poor connection.
  # We want the inner timeout (the SSH connection) to trigger before the outer (loop), to avoid the situation where we make two connections in parallel.
  INNER_TIMEOUT_SECONDS = 15
  OUTER_TIMEOUT_SECONDS = INNER_TIMEOUT_SECONDS + 1

  def initialize(host, user, local_port = 2288)
    @host, @user, @local_port = host, user, local_port
  end

  def open
    connect

    start_time = Time.now
    while true
      break if @up
      sleep 0.5

      if Time.now - start_time > OUTER_TIMEOUT_SECONDS
        puts "SSH connection failed, trying again... (#{@user}@#{@host})"
        start_time = Time.now
        connect
      end
    end
  end

  def connect
    @thread.kill if @thread
    @thread = Thread.new do
      Net::SSH.start(@host, @user, { :timeout => INNER_TIMEOUT_SECONDS }) do |ssh|
        ssh.forward.local(@local_port, 'localhost', Testbot::SERVER_PORT)
        ssh.loop {  @up = true }
      end
    end
  end
end
