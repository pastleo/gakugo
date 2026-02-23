# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias Gakugo.Learning
alias Gakugo.Learning.Unit
alias Gakugo.Repo

# Keep seeds notebook-first while legacy Grammar/Vocabulary/Flashcard flows are deprecated.
Repo.delete_all(Unit)

{:ok, unit} =
  Learning.create_unit(%{
    title: "Getting Started",
    from_target_lang: "JA-from-zh-TW"
  })

unit = Learning.get_unit!(unit.id)
default_page = hd(unit.pages)

{:ok, _grammar_page} =
  Learning.update_page(default_page, %{
    title: "Grammar",
    items: [
      %{
        "text" => "助詞「は」",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "text" => "說明句主詞（主題）",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => [
              %{
                "text" => "私は学生です。",
                "front" => false,
                "answer" => false,
                "link" => "",
                "children" => []
              },
              %{
                "text" => "彼は先生です。",
                "front" => false,
                "answer" => false,
                "link" => "",
                "children" => []
              }
            ]
          }
        ]
      },
      %{
        "text" => "助詞「の」",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "text" => "名詞修飾名詞",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => [
              %{
                "text" => "私の本です。",
                "front" => false,
                "answer" => false,
                "link" => "",
                "children" => []
              }
            ]
          }
        ]
      }
    ]
  })

{:ok, _vocab_page} =
  Learning.create_page(%{
    unit_id: unit.id,
    title: "Vocabularies",
    items: [
      %{
        "text" => "私（わたし）",
        "front" => true,
        "answer" => true,
        "link" => "",
        "children" => [
          %{
            "text" => "我",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      },
      %{
        "text" => "学生（がくせい）",
        "front" => true,
        "answer" => true,
        "link" => "",
        "children" => [
          %{
            "text" => "學生",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      },
      %{
        "text" => "先生（せんせい）",
        "front" => true,
        "answer" => true,
        "link" => "",
        "children" => [
          %{
            "text" => "老師、教授",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      }
    ]
  })

IO.puts("Seeds completed successfully!")
IO.puts("Created #{Repo.aggregate(Unit, :count)} units")
