defmodule Mudc.PromptTest do
  use ExUnit.Case

  test "recognizes MUME prompts with stats" do
    assert Mudc.Prompt.is_prompt?("*# CW A1 M1 P8 S3 XP:26.8k TP:0>") == true
    assert Mudc.Prompt.is_prompt?("o HP:100 Mana:50 Move:80>") == true
    assert Mudc.Prompt.is_prompt?("! CW HP:150>") == true
  end

  test "recognizes simple MUME prompts" do
    assert Mudc.Prompt.is_prompt?("*>") == true
    assert Mudc.Prompt.is_prompt?("o>") == true
    assert Mudc.Prompt.is_prompt?("!>") == true
  end

  test "recognizes menu prompts" do
    assert Mudc.Prompt.is_prompt?("Account>") == true
    assert Mudc.Prompt.is_prompt?("Character>") == true
  end

  test "rejects regular game text" do
    assert Mudc.Prompt.is_prompt?("You see a large tree here.") == false
    assert Mudc.Prompt.is_prompt?("A tall orc is standing here.") == false
    assert Mudc.Prompt.is_prompt?("The door is open.") == false
    assert Mudc.Prompt.is_prompt?("* W C HP:Healthy>look") == false
  end

  test "only checks current line after newline" do
    # Text with newline should only check what's after the newline
    assert Mudc.Prompt.is_prompt?("Some regular text\n*>") == true
    assert Mudc.Prompt.is_prompt?("*>\nSome regular text") == false
    assert Mudc.Prompt.is_prompt?("Line 1\nLine 2\n*# CW A1>") == true
  end

  test "handles empty or whitespace" do
    assert Mudc.Prompt.is_prompt?("") == false
    assert Mudc.Prompt.is_prompt?("   ") == false
    assert Mudc.Prompt.is_prompt?("\n") == false
  end
end
