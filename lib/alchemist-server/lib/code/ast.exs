Code.require_file "../helpers/introspection.exs", __DIR__

defmodule Alchemist.Code.Ast do

  @empty_metadata %{requires: [], imports: [], behavious: []}

  def extract_use_metadata(use_ast, module) do
    {_ast, metadata} =
      try do
        env = Map.put(__ENV__, :module, module)
        expand(use_ast, env)
      rescue
        e ->
          IO.puts(:stderr, "Expanding #{Macro.to_string(use_ast)} failed.")
          IO.puts(:stderr, Exception.message(e) <> "\n" <> Exception.format_stacktrace(System.stacktrace))
          {nil, @empty_metadata}
      end
    metadata
  end

  defp expand(ast, env) do
    {expanded_ast, _requires} = Macro.prewalk(ast, env, &do_expand/2)
    Macro.prewalk(expanded_ast, @empty_metadata, &pre_walk_expanded/2)
  end

  defp add_requires_to_env(modules, env) do
    requires_string = modules
      |> Enum.map(&"require #{Introspection.module_to_string(&1)}")
      |> Enum.join("; ")

    {new_env, _} = Code.eval_string("#{requires_string}; __ENV__", [], env)
    new_env
  end

  defp do_expand({:require, _, _} = ast, env) do
    modules = extract_directive_modules(:require, ast)
    new_env = add_requires_to_env(modules, env)
    {ast, new_env}
  end

  defp do_expand({name, _, _} = ast, env) when name in [:def, :defp, :import, :alias, :@, :defmacro, :defoverridable] do
    {ast, env}
  end

  defp do_expand(ast, env) do
    new_env = Map.put(env, :module, QrTag.Router)

    expanded_ast = Macro.expand(ast, new_env)
    {expanded_ast, new_env}
  end

  defp pre_walk_expanded({:__block__, _, _} = ast, acc) do
    {ast, acc}
  end
  defp pre_walk_expanded({:require, _, _} = ast, acc) do
    modules = extract_directive_modules(:require, ast)
    {ast, %{acc | requires: (acc.requires ++ modules)}}
  end
  defp pre_walk_expanded({:import, _, _} = ast, acc) do
    modules = extract_directive_modules(:import, ast)
    {ast, %{acc | imports: (acc.imports ++ modules)}}
  end
  defp pre_walk_expanded({:@, _, [{:behaviour, _, [module]}]} = ast, acc) do
    {ast, %{acc | behavious: [module|acc.behavious]}}
  end
  defp pre_walk_expanded({_name, _meta, _args}, acc) do
    {nil, acc}
  end
  defp pre_walk_expanded(ast, acc) do
    {ast, acc}
  end

  defp extract_directive_modules(directive, ast) do
    case ast do
      # v1.2 notation
      {^directive, _, [{{:., _, [{:__aliases__, _, prefix_atoms}, :{}]}, _, aliases}]} ->
        aliases |> Enum.map(fn {:__aliases__, _, mods} ->
          Module.concat(prefix_atoms ++ mods)
        end)
      # with options
      {^directive, _, [{_, _, module_atoms = [mod|_]}, _opts]} when is_atom(mod) ->
        [module_atoms |> Module.concat]
      # with options
      {^directive, _, [module, _opts]} when is_atom(module) ->
        [module]
      # with options
      {^directive, _, [{:__aliases__, _, module_parts}, _opts]} ->
        [module_parts |> Module.concat]
      # without options
      {^directive, _, [{:__aliases__, _, module_parts}]} ->
        [module_parts |> Module.concat]
      # without options
      {^directive, _, [{:__aliases__, [alias: false, counter: _], module_parts}]} ->
        [module_parts |> Module.concat]
      # without options
      {^directive, _, [module]} ->
        [module]
    end
  end
end
