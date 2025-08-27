namespace :character do
  desc "Interact with the Narrator AI chatbot"
  task :interact, [ :id ] => :environment do |t, args|
    character_id = args[:id]

    if character_id
      character = Character.find(character_id)
    else
      characters = Character.all

      if characters.empty?
        puts "No characters found. Please create a character first."
        return
      end

      puts "Available characters:"
      characters.each do |char|
        puts "#{char.id}: #{char.fullname}"
      end

      print "Enter the ID of the character you want to talk to: "
      selected_id = STDIN.gets.chomp.to_i

      character = Character.find_by(id: selected_id)

      if character.nil?
        puts "Invalid character ID. Please try again."
        return
      end
    end

    puts "Beginning conversation with Character '#{character.fullname}'..."
    puts "Type '/exit' to quit."

    chat = character.chat

    loop do
      print "> "
      user_input = STDIN.gets.chomp
      break if user_input.downcase == "/exit"

      final_message = chat.ask(user_input) do |chunk|
        puts chunk.content
      end

      puts final_message.content
    end

    puts "Thank you for interacting with '#{character.fullname}'!"
  end
end
