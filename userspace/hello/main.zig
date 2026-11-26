const std = @import("std");
const os = @import("doom_os");

export fn main() c_int {
    while(true){
        os.writeAll(1, "HELLO FROM USER SPACE") catch return -1;
    }
    return 0;
}
