///|
test "cpuinfo_model reads the first model name" {
  let cpuinfo =
    #|processor	: 0
    #|vendor_id	: GenuineIntel
    #|model name	: Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz
    #|
    #|processor	: 1
    #|model name	: Other
  assert_eq(
    cpuinfo_model(cpuinfo),
    Some("Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz"),
  )
  assert_eq(cpuinfo_model("processor\t: 0\nmodel name\n"), None)
  assert_eq(cpuinfo_model(""), None)
}

///|
async test "command_output returns None for a missing command" {
  assert_eq(command_output("mare-mark-no-such-command", []), None)
  assert_eq(command_output("sh", ["-c", "exit 3"]), None)
  assert_eq(command_output("sh", ["-c", "echo ' hi '"]), Some("hi"))
}
