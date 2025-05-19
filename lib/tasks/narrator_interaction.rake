namespace :narrator do
  desc "Interact with the Narrator AI chatbot"
  task interact: :environment do
    narrator = Narrator.new
    puts "Welcome to the Narrator AI Chatbot! Type 'exit' to quit."

    puts narrator.transcript.last[:assistant] if narrator.transcript.last[:assistant]

    loop do
      print "> "
      user_input = STDIN.gets.chomp
      break if user_input.downcase == "/exit"
      if user_input.downcase == "/save"
        narrator.save_transcript
        puts "Transcript saved!"
        next
      end
      if user_input.downcase == "/load"
        narrator.load_transcript
        puts "Transcript loaded!"
        puts narrator.transcript.last[:content]
        next
      end


      response = narrator.add_user_message(user_input)
      puts response
    end

    puts "Thank you for interacting with the Narrator!"
  end
end
