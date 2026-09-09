# THE FIXTURE THE SUBMISSION-RECEIPT BROWSER CHECK IS RUN AGAINST.
#
# Isolated and offline: a seeded world out of `db/seeds/worlds`, one playthrough
# standing in its opening room, and one of its own people made hostile so the
# battle panel is on the page beside the typed box. No model is ever asked
# anything -- the check never lets a turn run.
#
# THE QUEUED CONDITION IS THE POINT, and it is produced by what is NOT started:
# the server runs alone, with no `bin/jobs` worker, so every accepted submission
# sits in Solid Queue exactly as it does when the queue is behind an unfinished
# turn. That is the state `TurnsController#create` answers with a fresh token
# and no page at all, and the state the acknowledgement exists for.
#
#   bin/rails db:prepare && bin/rails db:seed
#   bin/rails runner .lavish/adversarial-review-2026-09-08/evaluation/submission-receipt-fixture.rb
#   PORT=3142 bin/rails server -p 3142 -b 127.0.0.1      # web only, no worker
#
# Never port 3000: the captain runs his own long-lived server there.
story = Story.find_by!(title: "The Salt Assizes")
opening = story.locations.realized.order(:id).first
game = Playthrough.create!(story: story, character: story.protagonist,
                           current_location: opening, current_scene: story.opening_scene)
foe = story.characters.find { |person| !person.is_protagonist? }
foe.update!(location: opening, hostile: true)

puts({ playthrough: game.id, room: opening.name, foe: foe.fullname,
       commands: game.commands.count }.to_json)
