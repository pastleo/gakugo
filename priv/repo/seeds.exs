# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Gakugo.Repo.insert!(%Gakugo.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Gakugo.Repo
alias Gakugo.Learning
alias Gakugo.Learning.{Unit, Vocabulary, Grammar}

# Clear existing data
Repo.delete_all(Grammar)
Repo.delete_all(Vocabulary)
Repo.delete_all(Unit)

# Create Units
{:ok, unit1} =
  Learning.create_unit(%{
    title: "1. Basic Greetings",
    target_lang: "ja",
    from_lang: "en"
  })

{:ok, unit2} =
  Learning.create_unit(%{
    title: "2: Numbers and Counting",
    target_lang: "ja",
    from_lang: "en"
  })

{:ok, unit3} =
  Learning.create_unit(%{
    title: "3: Common Verbs",
    target_lang: "ja",
    from_lang: "en"
  })

# Create Vocabularies for Unit 1 (Basic Greetings)
Learning.create_vocabulary(%{
  target: "私（わたし）",
  from: "我",
  note: "",
  unit_id: unit1.id
})

Learning.create_vocabulary(%{
  target: "あなた",
  from: "你、您",
  note: "",
  unit_id: unit1.id
})

Learning.create_vocabulary(%{
  target: "あの人（ひと）",
  from: "他、她、那個人",
  note: "",
  unit_id: unit1.id
})

Learning.create_vocabulary(%{
  target: "～さん",
  from: "～先生、～小姐、～女士",
  note: "",
  unit_id: unit1.id
})

Learning.create_vocabulary(%{
  target: "先生（せんせい）",
  from: "老師、教授",
  note: "",
  unit_id: unit1.id
})

Learning.create_vocabulary(%{
  target: "教師（きょうし）",
  from: "教師",
  note: "",
  unit_id: unit1.id
})

Learning.create_vocabulary(%{
  target: "学生（がくせい）",
  from: "學生",
  note: "",
  unit_id: unit1.id
})

Learning.create_vocabulary(%{
  target: "社員（しゃいん）",
  from: "公司職員",
  note: "",
  unit_id: unit1.id
})

# Create Vocabularies for Unit 2 (Numbers and Counting)
Learning.create_vocabulary(%{
  target: "いち",
  from: "one",
  note: "Number 1",
  unit_id: unit2.id
})

Learning.create_vocabulary(%{
  target: "に",
  from: "two",
  note: "Number 2",
  unit_id: unit2.id
})

Learning.create_vocabulary(%{
  target: "さん",
  from: "three",
  note: "Number 3",
  unit_id: unit2.id
})

Learning.create_vocabulary(%{
  target: "よん",
  from: "four",
  note: "Number 4, also pronounced as 'し' but 'よん' is more common",
  unit_id: unit2.id
})

Learning.create_vocabulary(%{
  target: "ご",
  from: "five",
  note: "Number 5",
  unit_id: unit2.id
})

# Create Vocabularies for Unit 3 (Common Verbs)
Learning.create_vocabulary(%{
  target: "たべる",
  from: "to eat",
  note: "Ichidan verb (ru-verb)",
  unit_id: unit3.id
})

Learning.create_vocabulary(%{
  target: "のむ",
  from: "to drink",
  note: "Godan verb (u-verb)",
  unit_id: unit3.id
})

Learning.create_vocabulary(%{
  target: "みる",
  from: "to see/watch",
  note: "Ichidan verb (ru-verb)",
  unit_id: unit3.id
})

Learning.create_vocabulary(%{
  target: "いく",
  from: "to go",
  note: "Godan verb (u-verb)",
  unit_id: unit3.id
})

Learning.create_vocabulary(%{
  target: "くる",
  from: "to come",
  note: "Irregular verb",
  unit_id: unit3.id
})

# Create Grammars for Unit 1 (Basic Greetings)
Learning.create_grammar(%{
  title: "助詞「は」",
  details: [
    %{
      "detail" => "說明句主詞（主題）",
      "children" => [
        %{"detail" => "彼は銀行員です。"},
        %{"detail" => "私は明日買い物に行きます。"}
      ]
    }
  ],
  unit_id: unit1.id
})

Learning.create_grammar(%{
  title: "敬体（丁寧体）：名詞",
  details: [
    %{
      "detail" => "非過去肯定：です",
      "children" => [
        %{"detail" => "あれは犬です"}
      ]
    },
    %{
      "detail" => "非過去否定：ではありません",
      "children" => [
        %{"detail" => "あれは犬ではありません"}
      ]
    },
    %{
      "detail" => "過去肯定：でした",
      "children" => [
        %{"detail" => "あれは犬でした"}
      ]
    },
    %{
      "detail" => "過去否定：ではありませんでした",
      "children" => [
        %{"detail" => "あれは犬ではありませんでした"}
      ]
    }
  ],
  unit_id: unit1.id
})

Learning.create_grammar(%{
  title: "助詞「か」",
  details: [
    %{
      "detail" => "疑問・不定",
      "children" => [
        %{"detail" => "そこは静かですか"}
      ]
    }
  ],
  unit_id: unit1.id
})

Learning.create_grammar(%{
  title: "助詞「の」",
  details: [
    %{
      "detail" => "名詞修飾名詞",
      "children" => [
        %{"detail" => "車のドア"}
      ]
    }
  ],
  unit_id: unit1.id
})

Learning.create_grammar(%{
  title: "助詞「も」",
  details: [
    %{
      "detail" => "類比・並列",
      "children" => [
        %{"detail" => "今晩焼き肉を食べました。お酒も飲みました"},
        %{"detail" => "私は今日も明日も残業します"}
      ]
    }
  ],
  unit_id: unit1.id
})

# Create Grammars for Unit 2 (Numbers and Counting)
Learning.create_grammar(%{
  title: "Number System",
  details: [
    %{
      "detail" => "Native Japanese numbers (ひとつ、ふたつ...)",
      "children" => [
        %{"detail" => "Used for counting general items up to 10"},
        %{"detail" => "Example: ひとつ (one thing), ふたつ (two things)"}
      ]
    },
    %{
      "detail" => "Sino-Japanese numbers (いち、に、さん...)",
      "children" => [
        %{
          "detail" => "Used with counters",
          "children" => [
            %{"detail" => "Example: 一人 (ひとり - one person)"},
            %{"detail" => "Example: 二本 (にほん - two long objects)"}
          ]
        },
        %{"detail" => "Used for mathematical operations"}
      ]
    }
  ],
  unit_id: unit2.id
})

# Create Grammars for Unit 3 (Common Verbs)
Learning.create_grammar(%{
  title: "Verb Groups",
  details: [
    %{
      "detail" => "Ichidan verbs (る-verbs)",
      "children" => [
        %{"detail" => "たべる - to eat"},
        %{"detail" => "みる - to see/watch"},
        %{"detail" => "Conjugation: Remove る, add ます for polite form"}
      ]
    },
    %{
      "detail" => "Godan verbs (う-verbs)",
      "children" => [
        %{"detail" => "のむ - to drink"},
        %{"detail" => "いく - to go"},
        %{"detail" => "Conjugation: Change う sound to い sound, add ます"}
      ]
    },
    %{
      "detail" => "Irregular verbs",
      "children" => [
        %{"detail" => "くる (来る) - to come → きます"},
        %{"detail" => "する - to do → します"}
      ]
    }
  ],
  unit_id: unit3.id
})

IO.puts("Seeds completed successfully!")
IO.puts("Created #{Repo.aggregate(Unit, :count)} units")
IO.puts("Created #{Repo.aggregate(Vocabulary, :count)} vocabularies")
IO.puts("Created #{Repo.aggregate(Grammar, :count)} grammars")
