#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
api_url="${KAGENT_API_URL:-http://127.0.0.1:18083}"
cli=("${KAGENT_CLI:-./kagent-darwin-arm64}" --api-url "$api_url" --gateway-url "$api_url" --timeout 90s)
session_id="$("${cli[@]}" agent session create --agent sre-readonly -o json | ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("session").fetch("id")')"
"${cli[@]}" agent invoke --session "$session_id" --task '请只回复：只读 SRE Agent 已连接模型。不要调用工具。' -o json | ruby -rjson -e '
x=JSON.parse(STDIN.read).fetch("task"); abort "Model task did not complete" unless x.dig("status","state")=="TASK_STATE_COMPLETED"; parts=(x["artifacts"]||[]).flat_map{|a|a["parts"]||[]}; abort "Missing expected model answer" unless parts.any?{|p|p["text"].to_s.include?("只读 SRE Agent 已连接模型")}; puts "PASS: real model response"'
"${cli[@]}" agent invoke --session "$session_id" --task '请实际调用 k8s_get_resources 查询 kagent 命名空间的 Pod，列出名称和就绪状态。不要查询 Secret、ConfigMap 内容、日志或其他命名空间。' -o json | ruby -rjson -e '
x=JSON.parse(STDIN.read).fetch("task"); abort "Tool task did not complete" unless x.dig("status","state")=="TASK_STATE_COMPLETED"; parts=(x["artifacts"]||[]).flat_map{|a|a["parts"]||[]}; calls=parts.select{|p|p.dig("metadata","kagent.dev/a2a/part-type")=="function_call"}; abort "Missing scoped MCP call" unless calls.any?{|p|p.dig("data","name")=="k8s_get_resources" && p.dig("data","args","namespace")=="kagent"}; results=parts.select{|p|p.dig("metadata","kagent.dev/a2a/part-type")=="function_response"}; abort "Missing successful MCP result" unless results.any?{|p|p.dig("data","name")=="k8s_get_resources" && p.dig("data","response").to_json.include?("kagent-controller")}; puts "PASS: actual scoped MCP call and response"; parts.each{|p|puts p["text"] if p["text"]}'
echo "Session: $session_id"
