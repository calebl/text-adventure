# THE LAST WORD ON THE RUN: what every story in this database looks like now.
#
# `Story::Doctor` reports and never writes (`AGENTS.md` -> *When a world
# outlives the schema*), which is why this is `reports_only?` -- it is asked
# once, its lines print whether or not anything above it changed, and a dry run
# is free to run it in full because there is nothing to hold back.
#
# It prints the headline per story and then only the findings NOTHING IN THE
# REGISTRY CAN ACT ON, because the ones it can act on have just been acted on
# by `Update::Steps::SafeRepairs` a step earlier. What is left is exactly the
# captain's remaining list, which is the summary this whole command is for.
class Update::Steps::Doctor < Update::Step
  def self.key = :doctor
  def self.reason = "report what is still wrong with every story, and which of it is by hand"
  def self.reports_only? = true

  # `Story::Doctor`'s remedy vocabulary, in the words `rake game:doctor` prints.
  REMEDY_LABELS = { safe: "repairable", generate: "model call", manual: "by hand" }.freeze

  def call
    doctors = Story::Doctor.all
    return report(changed: false, lines: [ "no stories in this database yet" ]) if doctors.empty?

    report(changed: false, lines: doctors.flat_map { |doctor| lines_for(doctor) } + [ tally(doctors) ])
  end

  private

  def lines_for(doctor)
    [ "##{doctor.story.id} #{doctor.story.title}: #{doctor.headline}" ] +
      doctor.findings.map do |finding|
        "     #{finding.fatal? ? "X" : "!"} [#{REMEDY_LABELS.fetch(finding.remedy)}] #{finding.message}"
      end
  end

  def tally(doctors)
    playable, unplayable = doctors.partition(&:playable?)
    healthy = doctors.count(&:healthy?)

    "#{doctors.size} stor#{doctors.one? ? "y" : "ies"}: #{healthy} healthy, " \
      "#{playable.size - healthy} playable with warnings, #{unplayable.size} unplayable"
  end
end
