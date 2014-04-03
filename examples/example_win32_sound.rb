#######################################################################
# example_win32_sound.rb (win32-sound)
#
# A example script to demonstrate the win32-sound library and for
# general futzing. You can run this via the 'rake example' task.
#
# Modify as you see fit.
#######################################################################
require 'win32/sound'
include Win32

wav = "c:\\windows\\media\\chimes.wav"

puts "VERSION: " + Sound::VERSION
#puts "Devices: " + Sound.devices.join(", ")

#Sound.volume = [77,128] # my personal settings

orig_left, orig_right = Sound.wave_volume
puts "Volume was: #{orig_left}, #{orig_right}"

#Sound.volume = 140
#puts "Volume is now: " + Sound.volume.join(", ")

#Sound.volume = [orig_left,orig_right]
#puts "Volume is now: " + Sound.volume.join(", ")

puts "Playing 'SystemAsterisk' sound"
sleep 1
Sound.play("SystemAsterisk",Sound::ALIAS)

puts "Playing 'chimes' sound once"
sleep 1
Sound.play(wav)

puts "Playing 'chimes' sound in a loop for 3 seconds"
sleep 1
Sound.play(wav,Sound::ASYNC|Sound::LOOP)
sleep 3
Sound.stop

puts "Playing default sound"
sleep 1
Sound.play("Foofoo", Sound::ALIAS)

puts "Playing a beep"
sleep 1
Sound.beep(500, 3000)

# waveOut functions work together to play PCM integer arrays directly
# to the sound device.
  
class Sound

  # Plays a frequency for a specified duration at a given volume.
  # Defaults are 440Hz, 1 second, full volume.
  # Result is a single channel, 44100Hz sampled, 16 bit sine wave.
  # If multiple instances are plays in simultaneous threads, 
  # they will be started and played at the same time.
  #
  # ex.: threads = []
  #      [440, 660].each do |freq|
  #        threads << Thread.new { Win32::Sound.play_freq(freq) }
  #      end
  #      threads.each { |th| th.join }
  #
  # the first frequency in this array (440) will wait until the
  # thread for 660 finished calculating its PCM array and they
  # will both start streaming at the same time.
  #
  def self.play_freq(frequency = 440, duration = 1000, volume = 1)
  
    if frequency > HIGH_FREQUENCY || frequency < LOW_FREQUENCY
      raise ArgumentError, 'invalid frequency'
    end
    
    if duration < 0 || duration > 5000
      raise ArgumentError, 'invalid duration'
    end
  
    stream { |wfx|
      data = generate_pcm_integer_array_for_freq(frequency, duration, volume)
      data_buffer = FFI::MemoryPointer.new(:int, data.size)
      data_buffer.write_array_of_int data
      buffer_length = wfx[:nAvgBytesPerSec]*duration/1000
      hdr = WAVEHDR.new
      hdr[:lpData] = data_buffer
      hdr[:dwBufferLength] = buffer_length
      hdr[:dwFlags] = 0
      hdr[:dwLoops] = 1
      hdr
    }
    
  end

  private
  
  # Sets up a ready-made waveOut stream to push a PCM integer array to.
  # It expects a block to be associated with the method call to which
  # it will yield an instance of WAVEFORMATEX that the block uses
  # to prepare a WAVEHDR to return to the function.
  # The WAVEHDR can contain either a self-made PCM integer array
  # or an array from a wav file or some other audio file converted
  # to PCM.
  # 
  # This function will take the entire PCM array and create one
  # giant buffer, so it is not intended for audio streams larger
  # than 5 seconds.
  #
  # In order to play larger audio files, you will have to use the waveOut
  # functions and structs to set up a double buffer to incrementally
  # push PCM data to.
  #
  def self.stream
  
    hWaveOut = HWAVEOUT.new
    wfx = WAVEFORMATEX.new

    wfx[:wFormatTag] = WAVE_FORMAT_PCM
    wfx[:nChannels] = 1
    wfx[:nSamplesPerSec] = 44100
    wfx[:wBitsPerSample] = 16
    wfx[:cbSize] = 0
    wfx[:nBlockAlign] = (wfx[:wBitsPerSample] >> 3) * wfx[:nChannels]
    wfx[:nAvgBytesPerSec] = wfx[:nBlockAlign] * wfx[:nSamplesPerSec]
    
    if ((error_code = waveOutOpen(hWaveOut.pointer, WAVE_MAPPER, wfx.pointer, 0, 0, 0)) != 0)
      raise SystemCallError.new('waveOutOpen', FFI.errno)
    end
    
    header = yield(wfx)
    
    if ((error_code = waveOutPrepareHeader(hWaveOut[:i], header.pointer, header.size)) != 0)
      raise SystemCallError.new('waveOutPrepareHeader', FFI.errno)
    end
    
    Thread.pass
    
    if (waveOutWrite(hWaveOut[:i], header.pointer, header.size) != 0)
      raise SystemCallError.new('waveOutWrite', FFI.errno)
    end
    
    while (waveOutUnprepareHeader(hWaveOut[:i], header.pointer, header.size) == 33)
      sleep 0.1
    end
    
    if ((error_code = waveOutClose(hWaveOut[:i])) != 0)
      raise SystemCallError.new('waveOutClose', FFI.errno)
    end
    
    self
  end
  
  # Generates an array of PCM integers to play a particular frequency
  # It also ramps up and down the volume in the first and last
  # 200 milliseconds to prevent audio clicking.
  # 
  def self.generate_pcm_integer_array_for_freq(freq, duration, volume)
  
    data = []
    ramp = 200.0
    samples = (44100/2*duration/1000.0).floor
    
    samples.times do |sample|
    
      angle = (2.0*Math::PI*freq) * sample/samples * duration/1000
      factor = Math.sin(angle)
      x = 32768.0*factor*volume
      
      if sample < ramp
        x *= sample/ramp
      end
      if samples - sample < ramp
        x *= (samples - sample)/ramp
      end
      
      data << x.floor
    end
    
    data
    
  end
  
end

# Now multiple tones can be played simultaneously

tones = [660.0, 880.0]
threads = []

tones.each do |tone|
  threads << Thread.new do
    puts "Playing tone of #{tone}Hz for 0.5 seconds"
    Sound.play_freq(tone, 500)
  end
end

threads.each {|t| t.join}
