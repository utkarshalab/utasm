;
; ============================================================================
; File        : src/arch/amd64.s
; Project     : utasm
; Description : AMD64 Mnemonic and Register Lookup Tables.
; ============================================================================
;

%include "include/macro.inc"
%include "include/constant.inc"
%include "include/arch/amd64.inc"

[SECTION .rodata]
align 8

global mnc_tb_x64
mnc_tb_x64:
    ; Generated from user-provided intel.txt
    mnc_ent "aaa", 0, 1000
    mnc_ent "aad", 0, 1001
    mnc_ent "aam", 0, 1002
    mnc_ent "aas", 0, 1003
    mnc_ent "adc", 0, 1004
    mnc_ent "adcx", 0, 1005
    mnc_ent "add", 0, 1006
    mnc_ent "addpd", 0, 1007
    mnc_ent "addps", 0, 1008
    mnc_ent "addsd", 0, 1009
    mnc_ent "addss", 0, 1010
    mnc_ent "addsubpd", 0, 1011
    mnc_ent "addsubps", 0, 1012
    mnc_ent "adox", 0, 1013
    mnc_ent "aesdec", 0, 1014
    mnc_ent "aesdec128kl", 0, 1015
    mnc_ent "aesdec256kl", 0, 1016
    mnc_ent "aesdeclast", 0, 1017
    mnc_ent "aesdecwide128kl", 0, 1018
    mnc_ent "aesdecwide256kl", 0, 1019
    mnc_ent "aesenc", 0, 1020
    mnc_ent "aesenc128kl", 0, 1021
    mnc_ent "aesenc256kl", 0, 1022
    mnc_ent "aesenclast", 0, 1023
    mnc_ent "aesencwide128kl", 0, 1024
    mnc_ent "aesencwide256kl", 0, 1025
    mnc_ent "aesimc", 0, 1026
    mnc_ent "aeskeygenassist", 0, 1027
    mnc_ent "and", 0, 1028
    mnc_ent "andn", 0, 1029
    mnc_ent "andnpd", 0, 1030
    mnc_ent "andnps", 0, 1031
    mnc_ent "andpd", 0, 1032
    mnc_ent "andps", 0, 1033
    mnc_ent "arpl", 0, 1034
    mnc_ent "bextr", 0, 1035
    mnc_ent "blendpd", 0, 1036
    mnc_ent "blendps", 0, 1037
    mnc_ent "blendvpd", 0, 1038
    mnc_ent "blendvps", 0, 1039
    mnc_ent "blsi", 0, 1040
    mnc_ent "blsmsk", 0, 1041
    mnc_ent "blsr", 0, 1042
    mnc_ent "bndcl", 0, 1043
    mnc_ent "bndcn", 0, 1044
    mnc_ent "bndcu", 0, 1045
    mnc_ent "bndldx", 0, 1046
    mnc_ent "bndmk", 0, 1047
    mnc_ent "bndmov", 0, 1048
    mnc_ent "bndstx", 0, 1049
    mnc_ent "bound", 0, 1050
    mnc_ent "bsf", 0, 1051
    mnc_ent "bsr", 0, 1052
    mnc_ent "bswap", 0, 1053
    mnc_ent "bt", 0, 1054
    mnc_ent "btc", 0, 1055
    mnc_ent "btr", 0, 1056
    mnc_ent "bts", 0, 1057
    mnc_ent "bzhi", 0, 1058
    mnc_ent "call", 0, 1059
    mnc_ent "cbw", 0, 1060
    mnc_ent "cdq", 0, 1061
    mnc_ent "cdqe", 0, 1062
    mnc_ent "clac", 0, 1063
    mnc_ent "clc", 0, 1064
    mnc_ent "cld", 0, 1065
    mnc_ent "cldemote", 0, 1066
    mnc_ent "clflush", 0, 1067
    mnc_ent "clflushopt", 0, 1068
    mnc_ent "cli", 0, 1069
    mnc_ent "clrssbsy", 0, 1070
    mnc_ent "clts", 0, 1071
    mnc_ent "clui", 0, 1072
    mnc_ent "clwb", 0, 1073
    mnc_ent "cmc", 0, 1074
    mnc_ent "cmp", 0, 1075
    mnc_ent "cmppd", 0, 1076
    mnc_ent "cmpps", 0, 1077
    mnc_ent "cmps", 0, 1078
    mnc_ent "cmpsb", 0, 1079
    mnc_ent "cmpsd", 0, 1080
    mnc_ent "cmpsq", 0, 1081
    mnc_ent "cmpss", 0, 1082
    mnc_ent "cmpsw", 0, 1083
    mnc_ent "cmpxchg", 0, 1084
    mnc_ent "cmpxchg16b", 0, 1085
    mnc_ent "cmpxchg8b", 0, 1086
    mnc_ent "comisd", 0, 1087
    mnc_ent "comiss", 0, 1088
    mnc_ent "cpuid", 0, 1089
    mnc_ent "cqo", 0, 1090
    mnc_ent "crc32", 0, 1091
    mnc_ent "cvtdq2pd", 0, 1092
    mnc_ent "cvtdq2ps", 0, 1093
    mnc_ent "cvtpd2dq", 0, 1094
    mnc_ent "cvtpd2pi", 0, 1095
    mnc_ent "cvtpd2ps", 0, 1096
    mnc_ent "cvtpi2pd", 0, 1097
    mnc_ent "cvtpi2ps", 0, 1098
    mnc_ent "cvtps2dq", 0, 1099
    mnc_ent "cvtps2pd", 0, 1100
    mnc_ent "cvtps2pi", 0, 1101
    mnc_ent "cvtsd2si", 0, 1102
    mnc_ent "cvtsd2ss", 0, 1103
    mnc_ent "cvtsi2sd", 0, 1104
    mnc_ent "cvtsi2ss", 0, 1105
    mnc_ent "cvtss2sd", 0, 1106
    mnc_ent "cvtss2si", 0, 1107
    mnc_ent "cvttpd2dq", 0, 1108
    mnc_ent "cvttpd2pi", 0, 1109
    mnc_ent "cvttps2dq", 0, 1110
    mnc_ent "cvttps2pi", 0, 1111
    mnc_ent "cvttsd2si", 0, 1112
    mnc_ent "cvttss2si", 0, 1113
    mnc_ent "cwd", 0, 1114
    mnc_ent "cwde", 0, 1115
    mnc_ent "daa", 0, 1116
    mnc_ent "das", 0, 1117
    mnc_ent "dec", 0, 1118
    mnc_ent "div", 0, 1119
    mnc_ent "divpd", 0, 1120
    mnc_ent "divps", 0, 1121
    mnc_ent "divsd", 0, 1122
    mnc_ent "divss", 0, 1123
    mnc_ent "dppd", 0, 1124
    mnc_ent "dpps", 0, 1125
    mnc_ent "emms", 0, 1126
    mnc_ent "encls", 0, 1127
    mnc_ent "encls[eadd]", 0, 1128
    mnc_ent "encls[eaug]", 0, 1129
    mnc_ent "encls[eblock]", 0, 1130
    mnc_ent "encls[ecreate]", 0, 1131
    mnc_ent "encls[edbgrd]", 0, 1132
    mnc_ent "encls[edbgwr]", 0, 1133
    mnc_ent "encls[eextend]", 0, 1134
    mnc_ent "encls[einit]", 0, 1135
    mnc_ent "encls[eldb]", 0, 1136
    mnc_ent "encls[eldbc]", 0, 1137
    mnc_ent "encls[eldu]", 0, 1138
    mnc_ent "encls[elduc]", 0, 1139
    mnc_ent "encls[emodpr]", 0, 1140
    mnc_ent "encls[emodt]", 0, 1141
    mnc_ent "encls[epa]", 0, 1142
    mnc_ent "encls[erdinfo]", 0, 1143
    mnc_ent "encls[eremove]", 0, 1144
    mnc_ent "encls[etrack]", 0, 1145
    mnc_ent "encls[etrackc]", 0, 1146
    mnc_ent "encls[ewb]", 0, 1147
    mnc_ent "enclu", 0, 1148
    mnc_ent "enclu[eaccept]", 0, 1149
    mnc_ent "enclu[eacceptcopy]", 0, 1150
    mnc_ent "enclu[edeccssa]", 0, 1151
    mnc_ent "enclu[eenter]", 0, 1152
    mnc_ent "enclu[eexit]", 0, 1153
    mnc_ent "enclu[egetkey]", 0, 1154
    mnc_ent "enclu[emodpe]", 0, 1155
    mnc_ent "enclu[ereport]", 0, 1156
    mnc_ent "enclu[eresume]", 0, 1157
    mnc_ent "enclv", 0, 1158
    mnc_ent "enclv[edecvirtchild]", 0, 1159
    mnc_ent "enclv[eincvirtchild]", 0, 1160
    mnc_ent "enclv[esetcontext]", 0, 1161
    mnc_ent "encodekey128", 0, 1162
    mnc_ent "encodekey256", 0, 1163
    mnc_ent "endbr32", 0, 1164
    mnc_ent "endbr64", 0, 1165
    mnc_ent "enqcmd", 0, 1166
    mnc_ent "enqcmds", 0, 1167
    mnc_ent "enter", 0, 1168
    mnc_ent "extractps", 0, 1169
    mnc_ent "f2xm1", 0, 1170
    mnc_ent "fabs", 0, 1171
    mnc_ent "fadd", 0, 1172
    mnc_ent "faddp", 0, 1173
    mnc_ent "fbld", 0, 1174
    mnc_ent "fbstp", 0, 1175
    mnc_ent "fchs", 0, 1176
    mnc_ent "fclex", 0, 1177
    mnc_ent "fcmovcc", 0, 1178
    mnc_ent "fcom", 0, 1179
    mnc_ent "fcomi", 0, 1180
    mnc_ent "fcomip", 0, 1181
    mnc_ent "fcomp", 0, 1182
    mnc_ent "fcompp", 0, 1183
    mnc_ent "fcos", 0, 1184
    mnc_ent "fdecstp", 0, 1185
    mnc_ent "fdiv", 0, 1186
    mnc_ent "fdivp", 0, 1187
    mnc_ent "fdivr", 0, 1188
    mnc_ent "fdivrp", 0, 1189
    mnc_ent "ffree", 0, 1190
    mnc_ent "fiadd", 0, 1191
    mnc_ent "ficom", 0, 1192
    mnc_ent "ficomp", 0, 1193
    mnc_ent "fidiv", 0, 1194
    mnc_ent "fidivr", 0, 1195
    mnc_ent "fild", 0, 1196
    mnc_ent "fimul", 0, 1197
    mnc_ent "fincstp", 0, 1198
    mnc_ent "finit", 0, 1199
    mnc_ent "fist", 0, 1200
    mnc_ent "fistp", 0, 1201
    mnc_ent "fisttp", 0, 1202
    mnc_ent "fisub", 0, 1203
    mnc_ent "fisubr", 0, 1204
    mnc_ent "fld", 0, 1205
    mnc_ent "fld1", 0, 1206
    mnc_ent "fldcw", 0, 1207
    mnc_ent "fldenv", 0, 1208
    mnc_ent "fldl2e", 0, 1209
    mnc_ent "fldl2t", 0, 1210
    mnc_ent "fldlg2", 0, 1211
    mnc_ent "fldln2", 0, 1212
    mnc_ent "fldpi", 0, 1213
    mnc_ent "fldz", 0, 1214
    mnc_ent "fmul", 0, 1215
    mnc_ent "fmulp", 0, 1216
    mnc_ent "fnclex", 0, 1217
    mnc_ent "fninit", 0, 1218
    mnc_ent "fnop", 0, 1219
    mnc_ent "fnsave", 0, 1220
    mnc_ent "fnstcw", 0, 1221
    mnc_ent "fnstenv", 0, 1222
    mnc_ent "fnstsw", 0, 1223
    mnc_ent "fpatan", 0, 1224
    mnc_ent "fprem", 0, 1225
    mnc_ent "fprem1", 0, 1226
    mnc_ent "fptan", 0, 1227
    mnc_ent "frndint", 0, 1228
    mnc_ent "frstor", 0, 1229
    mnc_ent "fsave", 0, 1230
    mnc_ent "fscale", 0, 1231
    mnc_ent "fsin", 0, 1232
    mnc_ent "fsincos", 0, 1233
    mnc_ent "fsqrt", 0, 1234
    mnc_ent "fst", 0, 1235
    mnc_ent "fstcw", 0, 1236
    mnc_ent "fstenv", 0, 1237
    mnc_ent "fstp", 0, 1238
    mnc_ent "fstsw", 0, 1239
    mnc_ent "fsub", 0, 1240
    mnc_ent "fsubp", 0, 1241
    mnc_ent "fsubr", 0, 1242
    mnc_ent "fsubrp", 0, 1243
    mnc_ent "ftst", 0, 1244
    mnc_ent "fucom", 0, 1245
    mnc_ent "fucomi", 0, 1246
    mnc_ent "fucomip", 0, 1247
    mnc_ent "fucomp", 0, 1248
    mnc_ent "fucompp", 0, 1249
    mnc_ent "fwait", 0, 1250
    mnc_ent "fxam", 0, 1251
    mnc_ent "fxch", 0, 1252
    mnc_ent "fxrstor", 0, 1253
    mnc_ent "fxsave", 0, 1254
    mnc_ent "fxtract", 0, 1255
    mnc_ent "fyl2x", 0, 1256
    mnc_ent "fyl2xp1", 0, 1257
    mnc_ent "getsec[capabilities]", 0, 1258
    mnc_ent "getsec[enteraccs]", 0, 1259
    mnc_ent "getsec[exitac]", 0, 1260
    mnc_ent "getsec[parameters]", 0, 1261
    mnc_ent "getsec[senter]", 0, 1262
    mnc_ent "getsec[sexit]", 0, 1263
    mnc_ent "getsec[smctrl]", 0, 1264
    mnc_ent "getsec[wakeup]", 0, 1265
    mnc_ent "gf2p8affineinvqb", 0, 1266
    mnc_ent "gf2p8affineqb", 0, 1267
    mnc_ent "gf2p8mulb", 0, 1268
    mnc_ent "haddpd", 0, 1269
    mnc_ent "haddps", 0, 1270
    mnc_ent "hlt", 0, 1271
    mnc_ent "hreset", 0, 1272
    mnc_ent "hsubpd", 0, 1273
    mnc_ent "hsubps", 0, 1274
    mnc_ent "idiv", 0, 1275
    mnc_ent "imul", 0, 1276
    mnc_ent "in", 0, 1277
    mnc_ent "inc", 0, 1278
    mnc_ent "incsspd", 0, 1279
    mnc_ent "incsspq", 0, 1280
    mnc_ent "ins", 0, 1281
    mnc_ent "insb", 0, 1282
    mnc_ent "insd", 0, 1283
    mnc_ent "insertps", 0, 1284
    mnc_ent "insw", 0, 1285
    mnc_ent "int", 0, 1286
    mnc_ent "int1", 0, 1287
    mnc_ent "int3", 0, 1288
    mnc_ent "into", 0, 1289
    mnc_ent "invd", 0, 1290
    mnc_ent "invept", 0, 1291
    mnc_ent "invlpg", 0, 1292
    mnc_ent "invpcid", 0, 1293
    mnc_ent "invvpid", 0, 1294
    mnc_ent "iret", 0, 1295
    mnc_ent "iretd", 0, 1296
    mnc_ent "iretq", 0, 1297
    mnc_ent "ja", 0, 3007
    mnc_ent "jae", 0, 3003
    mnc_ent "jb", 0, 3002
    mnc_ent "jbe", 0, 3006
    mnc_ent "jc", 0, 3002
    mnc_ent "je", 0, 3004
    mnc_ent "jg", 0, 3015
    mnc_ent "jge", 0, 3013
    mnc_ent "jl", 0, 3012
    mnc_ent "jle", 0, 3014
    mnc_ent "jna", 0, 3006
    mnc_ent "jnae", 0, 3002
    mnc_ent "jnb", 0, 3003
    mnc_ent "jnbe", 0, 3007
    mnc_ent "jnc", 0, 3003
    mnc_ent "jne", 0, 3005
    mnc_ent "jng", 0, 3014
    mnc_ent "jnge", 0, 3012
    mnc_ent "jnl", 0, 3013
    mnc_ent "jnle", 0, 3015
    mnc_ent "jno", 0, 3001
    mnc_ent "jnp", 0, 3011
    mnc_ent "jns", 0, 3009
    mnc_ent "jnz", 0, 3005
    mnc_ent "jo", 0, 3000
    mnc_ent "jp", 0, 3010
    mnc_ent "jpe", 0, 3010
    mnc_ent "jpo", 0, 3011
    mnc_ent "js", 0, 3008
    mnc_ent "jz", 0, 3004
    mnc_ent "cmovo", 0, 4000
    mnc_ent "cmovno", 0, 4001
    mnc_ent "cmovb", 0, 4002
    mnc_ent "cmovc", 0, 4002
    mnc_ent "cmovnae", 0, 4002
    mnc_ent "cmovae", 0, 4003
    mnc_ent "cmovnb", 0, 4003
    mnc_ent "cmovnc", 0, 4003
    mnc_ent "cmove", 0, 4004
    mnc_ent "cmovz", 0, 4004
    mnc_ent "cmovne", 0, 4005
    mnc_ent "cmovnz", 0, 4005
    mnc_ent "cmovbe", 0, 4006
    mnc_ent "cmovna", 0, 4006
    mnc_ent "cmova", 0, 4007
    mnc_ent "cmovnbe", 0, 4007
    mnc_ent "cmovs", 0, 4008
    mnc_ent "cmovns", 0, 4009
    mnc_ent "cmovp", 0, 4010
    mnc_ent "cmovpe", 0, 4010
    mnc_ent "cmovnp", 0, 4011
    mnc_ent "cmovpo", 0, 4011
    mnc_ent "cmovl", 0, 4012
    mnc_ent "cmovnge", 0, 4012
    mnc_ent "cmovge", 0, 4013
    mnc_ent "cmovnl", 0, 4013
    mnc_ent "cmovle", 0, 4014
    mnc_ent "cmovng", 0, 4014
    mnc_ent "cmovg", 0, 4015
    mnc_ent "cmovnle", 0, 4015
    mnc_ent "seto", 0, 4016
    mnc_ent "setno", 0, 4017
    mnc_ent "setb", 0, 4018
    mnc_ent "setc", 0, 4018
    mnc_ent "setnae", 0, 4018
    mnc_ent "setae", 0, 4019
    mnc_ent "setnb", 0, 4019
    mnc_ent "setnc", 0, 4019
    mnc_ent "sete", 0, 4020
    mnc_ent "setz", 0, 4020
    mnc_ent "setne", 0, 4021
    mnc_ent "setnz", 0, 4021
    mnc_ent "setbe", 0, 4022
    mnc_ent "setna", 0, 4022
    mnc_ent "seta", 0, 4023
    mnc_ent "setnbe", 0, 4023
    mnc_ent "sets", 0, 4024
    mnc_ent "setns", 0, 4025
    mnc_ent "setp", 0, 4026
    mnc_ent "setpe", 0, 4026
    mnc_ent "setnp", 0, 4027
    mnc_ent "setpo", 0, 4027
    mnc_ent "setl", 0, 4028
    mnc_ent "setnge", 0, 4028
    mnc_ent "setge", 0, 4029
    mnc_ent "setnl", 0, 4029
    mnc_ent "setle", 0, 4030
    mnc_ent "setng", 0, 4030
    mnc_ent "setg", 0, 4031
    mnc_ent "setnle", 0, 4031
    mnc_ent "jmp", 0, 1298
    mnc_ent "kaddb", 0, 1299
    mnc_ent "kaddd", 0, 1300
    mnc_ent "kaddq", 0, 1301
    mnc_ent "kaddw", 0, 1302
    mnc_ent "kandb", 0, 1303
    mnc_ent "kandd", 0, 1304
    mnc_ent "kandnb", 0, 1305
    mnc_ent "kandnd", 0, 1306
    mnc_ent "kandnq", 0, 1307
    mnc_ent "kandnw", 0, 1308
    mnc_ent "kandq", 0, 1309
    mnc_ent "kandw", 0, 1310
    mnc_ent "kmovb", 0, 1311
    mnc_ent "kmovd", 0, 1312
    mnc_ent "kmovq", 0, 1313
    mnc_ent "kmovw", 0, 1314
    mnc_ent "knotb", 0, 1315
    mnc_ent "knotd", 0, 1316
    mnc_ent "knotq", 0, 1317
    mnc_ent "knotw", 0, 1318
    mnc_ent "korb", 0, 1319
    mnc_ent "kord", 0, 1320
    mnc_ent "korq", 0, 1321
    mnc_ent "kortestb", 0, 1322
    mnc_ent "kortestd", 0, 1323
    mnc_ent "kortestq", 0, 1324
    mnc_ent "kortestw", 0, 1325
    mnc_ent "korw", 0, 1326
    mnc_ent "kshiftlb", 0, 1327
    mnc_ent "kshiftld", 0, 1328
    mnc_ent "kshiftlq", 0, 1329
    mnc_ent "kshiftlw", 0, 1330
    mnc_ent "kshiftrb", 0, 1331
    mnc_ent "kshiftrd", 0, 1332
    mnc_ent "kshiftrq", 0, 1333
    mnc_ent "kshiftrw", 0, 1334
    mnc_ent "ktestb", 0, 1335
    mnc_ent "ktestd", 0, 1336
    mnc_ent "ktestq", 0, 1337
    mnc_ent "ktestw", 0, 1338
    mnc_ent "kunpckbw", 0, 1339
    mnc_ent "kunpckdq", 0, 1340
    mnc_ent "kunpckwd", 0, 1341
    mnc_ent "kxnorb", 0, 1342
    mnc_ent "kxnord", 0, 1343
    mnc_ent "kxnorq", 0, 1344
    mnc_ent "kxnorw", 0, 1345
    mnc_ent "kxorb", 0, 1346
    mnc_ent "kxord", 0, 1347
    mnc_ent "kxorq", 0, 1348
    mnc_ent "kxorw", 0, 1349
    mnc_ent "lahf", 0, 1350
    mnc_ent "lar", 0, 1351
    mnc_ent "lddqu", 0, 1352
    mnc_ent "ldmxcsr", 0, 1353
    mnc_ent "lds", 0, 1354
    mnc_ent "ldtilecfg", 0, 1355
    mnc_ent "lea", 0, 1356
    mnc_ent "leave", 0, 1357
    mnc_ent "les", 0, 1358
    mnc_ent "lfence", 0, 1359
    mnc_ent "lfs", 0, 1360
    mnc_ent "lgdt", 0, 1361
    mnc_ent "lgs", 0, 1362
    mnc_ent "lidt", 0, 1363
    mnc_ent "lldt", 0, 1364
    mnc_ent "lmsw", 0, 1365
    mnc_ent "loadiwkey", 0, 1366
    mnc_ent "lock", 0, 1367
    mnc_ent "lods", 0, 1368
    mnc_ent "lodsb", 0, 1369
    mnc_ent "lodsd", 0, 1370
    mnc_ent "lodsq", 0, 1371
    mnc_ent "lodsw", 0, 1372
    mnc_ent "loop", 0, 1373
    mnc_ent "loopcc", 0, 1374
    mnc_ent "lsl", 0, 1375
    mnc_ent "lss", 0, 1376
    mnc_ent "ltr", 0, 1377
    mnc_ent "lzcnt", 0, 1378
    mnc_ent "maskmovdqu", 0, 1379
    mnc_ent "maskmovq", 0, 1380
    mnc_ent "maxpd", 0, 1381
    mnc_ent "maxps", 0, 1382
    mnc_ent "maxsd", 0, 1383
    mnc_ent "maxss", 0, 1384
    mnc_ent "mfence", 0, 1385
    mnc_ent "minpd", 0, 1386
    mnc_ent "minps", 0, 1387
    mnc_ent "minsd", 0, 1388
    mnc_ent "minss", 0, 1389
    mnc_ent "monitor", 0, 1390
    mnc_ent "mov", 0, 1391
    mnc_ent "movapd", 0, 1392
    mnc_ent "movaps", 0, 1393
    mnc_ent "movbe", 0, 1394
    mnc_ent "movd", 0, 1395
    mnc_ent "movddup", 0, 1396
    mnc_ent "movdir64b", 0, 1397
    mnc_ent "movdiri", 0, 1398
    mnc_ent "movdq2q", 0, 1399
    mnc_ent "movdqa", 0, 1400
    mnc_ent "movdqu", 0, 1401
    mnc_ent "movhlps", 0, 1402
    mnc_ent "movhpd", 0, 1403
    mnc_ent "movhps", 0, 1404
    mnc_ent "movlhps", 0, 1405
    mnc_ent "movlpd", 0, 1406
    mnc_ent "movlps", 0, 1407
    mnc_ent "movmskpd", 0, 1408
    mnc_ent "movmskps", 0, 1409
    mnc_ent "movntdq", 0, 1410
    mnc_ent "movntdqa", 0, 1411
    mnc_ent "movnti", 0, 1412
    mnc_ent "movntpd", 0, 1413
    mnc_ent "movntps", 0, 1414
    mnc_ent "movntq", 0, 1415
    mnc_ent "movq", 0, 1416
    mnc_ent "movq2dq", 0, 1417
    mnc_ent "movs", 0, 1418
    mnc_ent "movsb", 0, 1419
    mnc_ent "movsd", 0, 1420
    mnc_ent "movshdup", 0, 1421
    mnc_ent "movsldup", 0, 1422
    mnc_ent "movsq", 0, 1423
    mnc_ent "movss", 0, 1424
    mnc_ent "movsw", 0, 1425
    mnc_ent "movsx", 0, 1426
    mnc_ent "movsxd", 0, 1427
    mnc_ent "movupd", 0, 1428
    mnc_ent "movups", 0, 1429
    mnc_ent "movzx", 0, 1430
    mnc_ent "mpsadbw", 0, 1431
    mnc_ent "mul", 0, 1432
    mnc_ent "mulpd", 0, 1433
    mnc_ent "mulps", 0, 1434
    mnc_ent "mulsd", 0, 1435
    mnc_ent "mulss", 0, 1436
    mnc_ent "mulx", 0, 1437
    mnc_ent "mwait", 0, 1438
    mnc_ent "neg", 0, 1439
    mnc_ent "nop", 0, 1440
    mnc_ent "not", 0, 1441
    mnc_ent "or", 0, 1442
    mnc_ent "orpd", 0, 1443
    mnc_ent "orps", 0, 1444
    mnc_ent "out", 0, 1445
    mnc_ent "outs", 0, 1446
    mnc_ent "outsb", 0, 1447
    mnc_ent "outsd", 0, 1448
    mnc_ent "outsw", 0, 1449
    mnc_ent "pabsb", 0, 1450
    mnc_ent "pabsd", 0, 1451
    mnc_ent "pabsq", 0, 1452
    mnc_ent "pabsw", 0, 1453
    mnc_ent "packssdw", 0, 1454
    mnc_ent "packsswb", 0, 1455
    mnc_ent "packusdw", 0, 1456
    mnc_ent "packuswb", 0, 1457
    mnc_ent "paddb", 0, 1458
    mnc_ent "paddd", 0, 1459
    mnc_ent "paddq", 0, 1460
    mnc_ent "paddsb", 0, 1461
    mnc_ent "paddsw", 0, 1462
    mnc_ent "paddusb", 0, 1463
    mnc_ent "paddusw", 0, 1464
    mnc_ent "paddw", 0, 1465
    mnc_ent "palignr", 0, 1466
    mnc_ent "pand", 0, 1467
    mnc_ent "pandn", 0, 1468
    mnc_ent "pause", 0, 1469
    mnc_ent "pavgb", 0, 1470
    mnc_ent "pavgw", 0, 1471
    mnc_ent "pblendvb", 0, 1472
    mnc_ent "pblendw", 0, 1473
    mnc_ent "pclmulqdq", 0, 1474
    mnc_ent "pcmpeqb", 0, 1475
    mnc_ent "pcmpeqd", 0, 1476
    mnc_ent "pcmpeqq", 0, 1477
    mnc_ent "pcmpeqw", 0, 1478
    mnc_ent "pcmpestri", 0, 1479
    mnc_ent "pcmpestrm", 0, 1480
    mnc_ent "pcmpgtb", 0, 1481
    mnc_ent "pcmpgtd", 0, 1482
    mnc_ent "pcmpgtq", 0, 1483
    mnc_ent "pcmpgtw", 0, 1484
    mnc_ent "pcmpistri", 0, 1485
    mnc_ent "pcmpistrm", 0, 1486
    mnc_ent "pconfig", 0, 1487
    mnc_ent "pdep", 0, 1488
    mnc_ent "pext", 0, 1489
    mnc_ent "pextrb", 0, 1490
    mnc_ent "pextrd", 0, 1491
    mnc_ent "pextrq", 0, 1492
    mnc_ent "pextrw", 0, 1493
    mnc_ent "phaddd", 0, 1494
    mnc_ent "phaddsw", 0, 1495
    mnc_ent "phaddw", 0, 1496
    mnc_ent "phminposuw", 0, 1497
    mnc_ent "phsubd", 0, 1498
    mnc_ent "phsubsw", 0, 1499
    mnc_ent "phsubw", 0, 1500
    mnc_ent "pinsrb", 0, 1501
    mnc_ent "pinsrd", 0, 1502
    mnc_ent "pinsrq", 0, 1503
    mnc_ent "pinsrw", 0, 1504
    mnc_ent "pmaddubsw", 0, 1505
    mnc_ent "pmaddwd", 0, 1506
    mnc_ent "pmaxsb", 0, 1507
    mnc_ent "pmaxsd", 0, 1508
    mnc_ent "pmaxsq", 0, 1509
    mnc_ent "pmaxsw", 0, 1510
    mnc_ent "pmaxub", 0, 1511
    mnc_ent "pmaxud", 0, 1512
    mnc_ent "pmaxuq", 0, 1513
    mnc_ent "pmaxuw", 0, 1514
    mnc_ent "pminsb", 0, 1515
    mnc_ent "pminsd", 0, 1516
    mnc_ent "pminsq", 0, 1517
    mnc_ent "pminsw", 0, 1518
    mnc_ent "pminub", 0, 1519
    mnc_ent "pminud", 0, 1520
    mnc_ent "pminuq", 0, 1521
    mnc_ent "pminuw", 0, 1522
    mnc_ent "pmovmskb", 0, 1523
    mnc_ent "pmovsx", 0, 1524
    mnc_ent "pmovzx", 0, 1525
    mnc_ent "pmuldq", 0, 1526
    mnc_ent "pmulhrsw", 0, 1527
    mnc_ent "pmulhuw", 0, 1528
    mnc_ent "pmulhw", 0, 1529
    mnc_ent "pmulld", 0, 1530
    mnc_ent "pmullq", 0, 1531
    mnc_ent "pmullw", 0, 1532
    mnc_ent "pmuludq", 0, 1533
    mnc_ent "pop", 0, 1534
    mnc_ent "popa", 0, 1535
    mnc_ent "popad", 0, 1536
    mnc_ent "popcnt", 0, 1537
    mnc_ent "popf", 0, 1538
    mnc_ent "popfd", 0, 1539
    mnc_ent "popfq", 0, 1540
    mnc_ent "por", 0, 1541
    mnc_ent "prefetchh", 0, 1542
    mnc_ent "prefetchw", 0, 1543
    mnc_ent "prefetchwt1", 0, 1544
    mnc_ent "psadbw", 0, 1545
    mnc_ent "pshufb", 0, 1546
    mnc_ent "pshufd", 0, 1547
    mnc_ent "pshufhw", 0, 1548
    mnc_ent "pshuflw", 0, 1549
    mnc_ent "pshufw", 0, 1550
    mnc_ent "psignb", 0, 1551
    mnc_ent "psignd", 0, 1552
    mnc_ent "psignw", 0, 1553
    mnc_ent "pslld", 0, 1554
    mnc_ent "pslldq", 0, 1555
    mnc_ent "psllq", 0, 1556
    mnc_ent "psllw", 0, 1557
    mnc_ent "psrad", 0, 1558
    mnc_ent "psraq", 0, 1559
    mnc_ent "psraw", 0, 1560
    mnc_ent "psrld", 0, 1561
    mnc_ent "psrldq", 0, 1562
    mnc_ent "psrlq", 0, 1563
    mnc_ent "psrlw", 0, 1564
    mnc_ent "psubb", 0, 1565
    mnc_ent "psubd", 0, 1566
    mnc_ent "psubq", 0, 1567
    mnc_ent "psubsb", 0, 1568
    mnc_ent "psubsw", 0, 1569
    mnc_ent "psubusb", 0, 1570
    mnc_ent "psubusw", 0, 1571
    mnc_ent "psubw", 0, 1572
    mnc_ent "ptest", 0, 1573
    mnc_ent "ptwrite", 0, 1574
    mnc_ent "punpckhbw", 0, 1575
    mnc_ent "punpckhdq", 0, 1576
    mnc_ent "punpckhqdq", 0, 1577
    mnc_ent "punpckhwd", 0, 1578
    mnc_ent "punpcklbw", 0, 1579
    mnc_ent "punpckldq", 0, 1580
    mnc_ent "punpcklqdq", 0, 1581
    mnc_ent "punpcklwd", 0, 1582
    mnc_ent "push", 0, 1583
    mnc_ent "pusha", 0, 1584
    mnc_ent "pushad", 0, 1585
    mnc_ent "pushf", 0, 1586
    mnc_ent "pushfd", 0, 1587
    mnc_ent "pushfq", 0, 1588
    mnc_ent "pxor", 0, 1589
    mnc_ent "rcl", 0, 1590
    mnc_ent "rcpps", 0, 1591
    mnc_ent "rcpss", 0, 1592
    mnc_ent "rcr", 0, 1593
    mnc_ent "rdfsbase", 0, 1594
    mnc_ent "rdgsbase", 0, 1595
    mnc_ent "rdmsr", 0, 1596
    mnc_ent "rdpid", 0, 1597
    mnc_ent "rdpkru", 0, 1598
    mnc_ent "rdpmc", 0, 1599
    mnc_ent "rdrand", 0, 1600
    mnc_ent "rdseed", 0, 1601
    mnc_ent "rdsspd", 0, 1602
    mnc_ent "rdsspq", 0, 1603
    mnc_ent "rdtsc", 0, 1604
    mnc_ent "rdtscp", 0, 1605
    mnc_ent "rep", 0, 1606
    mnc_ent "repe", 0, 1607
    mnc_ent "repne", 0, 1608
    mnc_ent "repnz", 0, 1609
    mnc_ent "repz", 0, 1610
    mnc_ent "ret", 0, 1611
    mnc_ent "rol", 0, 1612
    mnc_ent "ror", 0, 1613
    mnc_ent "rorx", 0, 1614
    mnc_ent "roundpd", 0, 1615
    mnc_ent "roundps", 0, 1616
    mnc_ent "roundsd", 0, 1617
    mnc_ent "roundss", 0, 1618
    mnc_ent "rsm", 0, 1619
    mnc_ent "rsqrtps", 0, 1620
    mnc_ent "rsqrtss", 0, 1621
    mnc_ent "rstorssp", 0, 1622
    mnc_ent "sahf", 0, 1623
    mnc_ent "sal", 0, 1624
    mnc_ent "sar", 0, 1625
    mnc_ent "sarx", 0, 1626
    mnc_ent "saveprevssp", 0, 1627
    mnc_ent "sbb", 0, 1628
    mnc_ent "scas", 0, 1629
    mnc_ent "scasb", 0, 1630
    mnc_ent "scasd", 0, 1631
    mnc_ent "scasw", 0, 1632
    mnc_ent "senduipi", 0, 1633
    mnc_ent "serialize", 0, 1634
    mnc_ent "setcc", 0, 1635
    mnc_ent "setssbsy", 0, 1636
    mnc_ent "sfence", 0, 1637
    mnc_ent "sgdt", 0, 1638
    mnc_ent "sgx", 0, 1639
    mnc_ent "sha1msg1", 0, 1640
    mnc_ent "sha1msg2", 0, 1641
    mnc_ent "sha1nexte", 0, 1642
    mnc_ent "sha1rnds4", 0, 1643
    mnc_ent "sha256msg1", 0, 1644
    mnc_ent "sha256msg2", 0, 1645
    mnc_ent "sha256rnds2", 0, 1646
    mnc_ent "shl", 0, 1647
    mnc_ent "shld", 0, 1648
    mnc_ent "shlx", 0, 1649
    mnc_ent "shr", 0, 1650
    mnc_ent "shrd", 0, 1651
    mnc_ent "shrx", 0, 1652
    mnc_ent "shufpd", 0, 1653
    mnc_ent "shufps", 0, 1654
    mnc_ent "sidt", 0, 1655
    mnc_ent "sldt", 0, 1656
    mnc_ent "smsw", 0, 1657
    mnc_ent "smx", 0, 1658
    mnc_ent "sqrtpd", 0, 1659
    mnc_ent "sqrtps", 0, 1660
    mnc_ent "sqrtsd", 0, 1661
    mnc_ent "sqrtss", 0, 1662
    mnc_ent "stac", 0, 1663
    mnc_ent "stc", 0, 1664
    mnc_ent "std", 0, 1665
    mnc_ent "sti", 0, 1666
    mnc_ent "stmxcsr", 0, 1667
    mnc_ent "stos", 0, 1668
    mnc_ent "stosb", 0, 1669
    mnc_ent "stosd", 0, 1670
    mnc_ent "stosq", 0, 1671
    mnc_ent "stosw", 0, 1672
    mnc_ent "str", 0, 1673
    mnc_ent "sttilecfg", 0, 1674
    mnc_ent "stui", 0, 1675
    mnc_ent "sub", 0, 1676
    mnc_ent "subpd", 0, 1677
    mnc_ent "subps", 0, 1678
    mnc_ent "subsd", 0, 1679
    mnc_ent "subss", 0, 1680
    mnc_ent "swapgs", 0, 1681
    mnc_ent "syscall", 0, 1682
    mnc_ent "sysenter", 0, 1683
    mnc_ent "sysexit", 0, 1684
    mnc_ent "sysret", 0, 1685
    mnc_ent "tdpbf16ps", 0, 1686
    mnc_ent "tdpbssd", 0, 1687
    mnc_ent "tdpbsud", 0, 1688
    mnc_ent "tdpbusd", 0, 1689
    mnc_ent "tdpbuud", 0, 1690
    mnc_ent "test", 0, 1691
    mnc_ent "testui", 0, 1692
    mnc_ent "tileloadd", 0, 1693
    mnc_ent "tileloaddt1", 0, 1694
    mnc_ent "tilerelease", 0, 1695
    mnc_ent "tilestored", 0, 1696
    mnc_ent "tilezero", 0, 1697
    mnc_ent "tpause", 0, 1698
    mnc_ent "tzcnt", 0, 1699
    mnc_ent "ucomisd", 0, 1700
    mnc_ent "ucomiss", 0, 1701
    mnc_ent "ud", 0, 1702
    mnc_ent "uiret", 0, 1703
    mnc_ent "umonitor", 0, 1704
    mnc_ent "umwait", 0, 1705
    mnc_ent "unpckhpd", 0, 1706
    mnc_ent "unpckhps", 0, 1707
    mnc_ent "unpcklpd", 0, 1708
    mnc_ent "unpcklps", 0, 1709
    mnc_ent "v4fmaddps", 0, 1710
    mnc_ent "v4fmaddss", 0, 1711
    mnc_ent "v4fnmaddps", 0, 1712
    mnc_ent "v4fnmaddss", 0, 1713
    mnc_ent "vaddph", 0, 1714
    mnc_ent "vaddps", 0, ID_VADDPS
    mnc_ent "vaddsh", 0, 1715
    mnc_ent "vmovups", 0, ID_VMOVUPS
    mnc_ent "vxorps", 0, ID_VXORPS
    mnc_ent "valignd", 0, 1716
    mnc_ent "valignq", 0, 1717
    mnc_ent "vblendmpd", 0, 1718
    mnc_ent "vblendmps", 0, 1719
    mnc_ent "vbroadcast", 0, 1720
    mnc_ent "vcmpph", 0, 1721
    mnc_ent "vcmpsh", 0, 1722
    mnc_ent "vcomish", 0, 1723
    mnc_ent "vcompresspd", 0, 1724
    mnc_ent "vcompressps", 0, 1725
    mnc_ent "vcompressw", 0, 1726
    mnc_ent "vcvtdq2ph", 0, 1727
    mnc_ent "vcvtne2ps2bf16", 0, 1728
    mnc_ent "vcvtneps2bf16", 0, 1729
    mnc_ent "vcvtpd2ph", 0, 1730
    mnc_ent "vcvtpd2qq", 0, 1731
    mnc_ent "vcvtpd2udq", 0, 1732
    mnc_ent "vcvtpd2uqq", 0, 1733
    mnc_ent "vcvtph2dq", 0, 1734
    mnc_ent "vcvtph2pd", 0, 1735
    mnc_ent "vcvtph2ps", 0, 1736
    mnc_ent "vcvtph2psx", 0, 1737
    mnc_ent "vcvtph2qq", 0, 1738
    mnc_ent "vcvtph2udq", 0, 1739
    mnc_ent "vcvtph2uqq", 0, 1740
    mnc_ent "vcvtph2uw", 0, 1741
    mnc_ent "vcvtph2w", 0, 1742
    mnc_ent "vcvtps2ph", 0, 1743
    mnc_ent "vcvtps2phx", 0, 1744
    mnc_ent "vcvtps2qq", 0, 1745
    mnc_ent "vcvtps2udq", 0, 1746
    mnc_ent "vcvtps2uqq", 0, 1747
    mnc_ent "vcvtqq2pd", 0, 1748
    mnc_ent "vcvtqq2ph", 0, 1749
    mnc_ent "vcvtqq2ps", 0, 1750
    mnc_ent "vcvtsd2sh", 0, 1751
    mnc_ent "vcvtsd2usi", 0, 1752
    mnc_ent "vcvtsh2sd", 0, 1753
    mnc_ent "vcvtsh2si", 0, 1754
    mnc_ent "vcvtsh2ss", 0, 1755
    mnc_ent "vcvtsh2usi", 0, 1756
    mnc_ent "vcvtsi2sh", 0, 1757
    mnc_ent "vcvtss2sh", 0, 1758
    mnc_ent "vcvtss2usi", 0, 1759
    mnc_ent "vcvttpd2qq", 0, 1760
    mnc_ent "vcvttpd2udq", 0, 1761
    mnc_ent "vcvttpd2uqq", 0, 1762
    mnc_ent "vcvttph2dq", 0, 1763
    mnc_ent "vcvttph2qq", 0, 1764
    mnc_ent "vcvttph2udq", 0, 1765
    mnc_ent "vcvttph2uqq", 0, 1766
    mnc_ent "vcvttph2uw", 0, 1767
    mnc_ent "vcvttph2w", 0, 1768
    mnc_ent "vcvttps2qq", 0, 1769
    mnc_ent "vcvttps2udq", 0, 1770
    mnc_ent "vcvttps2uqq", 0, 1771
    mnc_ent "vcvttsd2usi", 0, 1772
    mnc_ent "vcvttsh2si", 0, 1773
    mnc_ent "vcvttsh2usi", 0, 1774
    mnc_ent "vcvttss2usi", 0, 1775
    mnc_ent "vcvtudq2pd", 0, 1776
    mnc_ent "vcvtudq2ph", 0, 1777
    mnc_ent "vcvtudq2ps", 0, 1778
    mnc_ent "vcvtuqq2pd", 0, 1779
    mnc_ent "vcvtuqq2ph", 0, 1780
    mnc_ent "vcvtuqq2ps", 0, 1781
    mnc_ent "vcvtusi2sd", 0, 1782
    mnc_ent "vcvtusi2sh", 0, 1783
    mnc_ent "vcvtusi2ss", 0, 1784
    mnc_ent "vcvtuw2ph", 0, 1785
    mnc_ent "vcvtw2ph", 0, 1786
    mnc_ent "vdbpsadbw", 0, 1787
    mnc_ent "vdivph", 0, 1788
    mnc_ent "vdivsh", 0, 1789
    mnc_ent "vdpbf16ps", 0, 1790
    mnc_ent "verr", 0, 1791
    mnc_ent "verw", 0, 1792
    mnc_ent "vexp2pd", 0, 1793
    mnc_ent "vexp2ps", 0, 1794
    mnc_ent "vexpandpd", 0, 1795
    mnc_ent "vexpandps", 0, 1796
    mnc_ent "vextractf128", 0, 1797
    mnc_ent "vextractf32x4", 0, 1798
    mnc_ent "vextractf32x8", 0, 1799
    mnc_ent "vextractf64x2", 0, 1800
    mnc_ent "vextractf64x4", 0, 1801
    mnc_ent "vextracti128", 0, 1802
    mnc_ent "vextracti32x4", 0, 1803
    mnc_ent "vextracti32x8", 0, 1804
    mnc_ent "vextracti64x2", 0, 1805
    mnc_ent "vextracti64x4", 0, 1806
    mnc_ent "vfcmaddcph", 0, 1807
    mnc_ent "vfcmaddcsh", 0, 1808
    mnc_ent "vfcmulcph", 0, 1809
    mnc_ent "vfcmulcsh", 0, 1810
    mnc_ent "vfixupimmpd", 0, 1811
    mnc_ent "vfixupimmps", 0, 1812
    mnc_ent "vfixupimmsd", 0, 1813
    mnc_ent "vfixupimmss", 0, 1814
    mnc_ent "vfmadd132pd", 0, 1815
    mnc_ent "vfmadd132ph", 0, 1816
    mnc_ent "vfmadd132ps", 0, 1817
    mnc_ent "vfmadd132sd", 0, 1818
    mnc_ent "vfmadd132sh", 0, 1819
    mnc_ent "vfmadd132ss", 0, 1820
    mnc_ent "vfmadd213pd", 0, 1821
    mnc_ent "vfmadd213ph", 0, 1822
    mnc_ent "vfmadd213ps", 0, 1823
    mnc_ent "vfmadd213sd", 0, 1824
    mnc_ent "vfmadd213sh", 0, 1825
    mnc_ent "vfmadd213ss", 0, 1826
    mnc_ent "vfmadd231pd", 0, 1827
    mnc_ent "vfmadd231ph", 0, 1828
    mnc_ent "vfmadd231ps", 0, 1829
    mnc_ent "vfmadd231sd", 0, 1830
    mnc_ent "vfmadd231sh", 0, 1831
    mnc_ent "vfmadd231ss", 0, 1832
    mnc_ent "vfmaddcph", 0, 1833
    mnc_ent "vfmaddcsh", 0, 1834
    mnc_ent "vfmaddrnd231pd", 0, 1835
    mnc_ent "vfmadsub132pd", 0, 1836
    mnc_ent "vfmadsub132ph", 0, 1837
    mnc_ent "vfmadsub132ps", 0, 1838
    mnc_ent "vfmadsub213pd", 0, 1839
    mnc_ent "vfmadsub213ph", 0, 1840
    mnc_ent "vfmadsub213ps", 0, 1841
    mnc_ent "vfmadsub231pd", 0, 1842
    mnc_ent "vfmadsub231ph", 0, 1843
    mnc_ent "vfmadsub231ps", 0, 1844
    mnc_ent "vfmsub132pd", 0, 1845
    mnc_ent "vfmsub132ph", 0, 1846
    mnc_ent "vfmsub132ps", 0, 1847
    mnc_ent "vfmsub132sd", 0, 1848
    mnc_ent "vfmsub132sh", 0, 1849
    mnc_ent "vfmsub132ss", 0, 1850
    mnc_ent "vfmsub213pd", 0, 1851
    mnc_ent "vfmsub213ph", 0, 1852
    mnc_ent "vfmsub213ps", 0, 1853
    mnc_ent "vfmsub213sd", 0, 1854
    mnc_ent "vfmsub213sh", 0, 1855
    mnc_ent "vfmsub213ss", 0, 1856
    mnc_ent "vfmsub231pd", 0, 1857
    mnc_ent "vfmsub231ph", 0, 1858
    mnc_ent "vfmsub231ps", 0, 1859
    mnc_ent "vfmsub231sd", 0, 1860
    mnc_ent "vfmsub231sh", 0, 1861
    mnc_ent "vfmsub231ss", 0, 1862
    mnc_ent "vfmsubadd132pd", 0, 1863
    mnc_ent "vfmsubadd132ph", 0, 1864
    mnc_ent "vfmsubadd132ps", 0, 1865
    mnc_ent "vfmsubadd213pd", 0, 1866
    mnc_ent "vfmsubadd213ph", 0, 1867
    mnc_ent "vfmsubadd213ps", 0, 1868
    mnc_ent "vfmsubadd231pd", 0, 1869
    mnc_ent "vfmsubadd231ph", 0, 1870
    mnc_ent "vfmsubadd231ps", 0, 1871
    mnc_ent "vfmulcph", 0, 1872
    mnc_ent "vfmulcsh", 0, 1873
    mnc_ent "vfnmadd132pd", 0, 1874
    mnc_ent "vfnmadd132ph", 0, 1875
    mnc_ent "vfnmadd132ps", 0, 1876
    mnc_ent "vfnmadd132sd", 0, 1877
    mnc_ent "vfnmadd132sh", 0, 1878
    mnc_ent "vfnmadd132ss", 0, 1879
    mnc_ent "vfnmadd213pd", 0, 1880
    mnc_ent "vfnmadd213ph", 0, 1881
    mnc_ent "vfnmadd213ps", 0, 1882
    mnc_ent "vfnmadd213sd", 0, 1883
    mnc_ent "vfnmadd213sh", 0, 1884
    mnc_ent "vfnmadd213ss", 0, 1885
    mnc_ent "vfnmadd231pd", 0, 1886
    mnc_ent "vfnmadd231ph", 0, 1887
    mnc_ent "vfnmadd231ps", 0, 1888
    mnc_ent "vfnmadd231sd", 0, 1889
    mnc_ent "vfnmadd231sh", 0, 1890
    mnc_ent "vfnmadd231ss", 0, 1891
    mnc_ent "vfnmsub132pd", 0, 1892
    mnc_ent "vfnmsub132ph", 0, 1893
    mnc_ent "vfnmsub132ps", 0, 1894
    mnc_ent "vfnmsub132sd", 0, 1895
    mnc_ent "vfnmsub132sh", 0, 1896
    mnc_ent "vfnmsub132ss", 0, 1897
    mnc_ent "vfnmsub213pd", 0, 1898
    mnc_ent "vfnmsub213ph", 0, 1899
    mnc_ent "vfnmsub213ps", 0, 1900
    mnc_ent "vfnmsub213sd", 0, 1901
    mnc_ent "vfnmsub213sh", 0, 1902
    mnc_ent "vfnmsub213ss", 0, 1903
    mnc_ent "vfnmsub231pd", 0, 1904
    mnc_ent "vfnmsub231ph", 0, 1905
    mnc_ent "vfnmsub231ps", 0, 1906
    mnc_ent "vfnmsub231sd", 0, 1907
    mnc_ent "vfnmsub231sh", 0, 1908
    mnc_ent "vfnmsub231ss", 0, 1909
    mnc_ent "vfpclasspd", 0, 1910
    mnc_ent "vfpclassph", 0, 1911
    mnc_ent "vfpclassps", 0, 1912
    mnc_ent "vfpclasssd", 0, 1913
    mnc_ent "vfpclasssh", 0, 1914
    mnc_ent "vfpclassss", 0, 1915
    mnc_ent "vgatherdpd", 0, 1916
    mnc_ent "vgatherdps", 0, 1917
    mnc_ent "vgatherqpd", 0, 1918
    mnc_ent "vgatherqps", 0, 1919
    mnc_ent "vgetexppd", 0, 1920
    mnc_ent "vgetexpph", 0, 1921
    mnc_ent "vgetexpps", 0, 1922
    mnc_ent "vgetexpsd", 0, 1923
    mnc_ent "vgetexpsh", 0, 1924
    mnc_ent "vgetexpss", 0, 1925
    mnc_ent "vgetmantpd", 0, 1926
    mnc_ent "vgetmantph", 0, 1927
    mnc_ent "vgetmantps", 0, 1928
    mnc_ent "vgetmantsd", 0, 1929
    mnc_ent "vgetmantsh", 0, 1930
    mnc_ent "vgetmantss", 0, 1931
    mnc_ent "vinsertf128", 0, 1932
    mnc_ent "vinsertf32x4", 0, 1933
    mnc_ent "vinsertf32x8", 0, 1934
    mnc_ent "vinsertf64x2", 0, 1935
    mnc_ent "vinsertf64x4", 0, 1936
    mnc_ent "vinserti128", 0, 1937
    mnc_ent "vinserti32x4", 0, 1938
    mnc_ent "vinserti32x8", 0, 1939
    mnc_ent "vinserti64x2", 0, 1940
    mnc_ent "vinserti64x4", 0, 1941
    mnc_ent "vmaskmov", 0, 1942
    mnc_ent "vmaxph", 0, 1943
    mnc_ent "vmaxsh", 0, 1944
    mnc_ent "vminph", 0, 1945
    mnc_ent "vminsh", 0, 1946
    mnc_ent "vmovdqa32", 0, 1947
    mnc_ent "vmovdqa64", 0, 1948
    mnc_ent "vmovdqu16", 0, 1949
    mnc_ent "vmovdqu32", 0, 1950
    mnc_ent "vmovdqu64", 0, 1951
    mnc_ent "vmovdqu8", 0, 1952
    mnc_ent "vmovsh", 0, 1953
    mnc_ent "vmovw", 0, 1954
    mnc_ent "vmulph", 0, 1955
    mnc_ent "vmulsh", 0, 1956
    mnc_ent "vp2intersectd", 0, 1957
    mnc_ent "vp2intersectq", 0, 1958
    mnc_ent "vpblendd", 0, 1959
    mnc_ent "vpblendmb", 0, 1960
    mnc_ent "vpblendmd", 0, 1961
    mnc_ent "vpblendmq", 0, 1962
    mnc_ent "vpblendmw", 0, 1963
    mnc_ent "vpbroadcast", 0, 1964
    mnc_ent "vpbroadcastb", 0, 1965
    mnc_ent "vpbroadcastd", 0, 1966
    mnc_ent "vpbroadcastm", 0, 1967
    mnc_ent "vpbroadcastq", 0, 1968
    mnc_ent "vpbroadcastw", 0, 1969
    mnc_ent "vpcmpb", 0, 1970
    mnc_ent "vpcmpd", 0, 1971
    mnc_ent "vpcmpq", 0, 1972
    mnc_ent "vpcmpub", 0, 1973
    mnc_ent "vpcmpud", 0, 1974
    mnc_ent "vpcmpuq", 0, 1975
    mnc_ent "vpcmpuw", 0, 1976
    mnc_ent "vpcmpw", 0, 1977
    mnc_ent "vpcompressb", 0, 1978
    mnc_ent "vpcompressd", 0, 1979
    mnc_ent "vpcompressq", 0, 1980
    mnc_ent "vpconflictd", 0, 1981
    mnc_ent "vpconflictq", 0, 1982
    mnc_ent "vpdpbusd", 0, 1983
    mnc_ent "vpdpbusds", 0, 1984
    mnc_ent "vpdpwssd", 0, 1985
    mnc_ent "vpdpwssds", 0, 1986
    mnc_ent "vperm2f128", 0, 1987
    mnc_ent "vperm2i128", 0, 1988
    mnc_ent "vpermb", 0, 1989
    mnc_ent "vpermd", 0, 1990
    mnc_ent "vpermi2b", 0, 1991
    mnc_ent "vpermi2d", 0, 1992
    mnc_ent "vpermi2pd", 0, 1993
    mnc_ent "vpermi2ps", 0, 1994
    mnc_ent "vpermi2q", 0, 1995
    mnc_ent "vpermi2w", 0, 1996
    mnc_ent "vpermilpd", 0, 1997
    mnc_ent "vpermilps", 0, 1998
    mnc_ent "vpermpd", 0, 1999
    mnc_ent "vpermps", 0, 2000
    mnc_ent "vpermq", 0, 2001
    mnc_ent "vpermt2b", 0, 2002
    mnc_ent "vpermt2d", 0, 2003
    mnc_ent "vpermt2pd", 0, 2004
    mnc_ent "vpermt2ps", 0, 2005
    mnc_ent "vpermt2q", 0, 2006
    mnc_ent "vpermt2w", 0, 2007
    mnc_ent "vpermw", 0, 2008
    mnc_ent "vpexpandb", 0, 2009
    mnc_ent "vpexpandd", 0, 2010
    mnc_ent "vpexpandq", 0, 2011
    mnc_ent "vpexpandw", 0, 2012
    mnc_ent "vpgatherdd", 0, 2013
    mnc_ent "vpgatherdq", 0, 2014
    mnc_ent "vpgatherqd", 0, 2015
    mnc_ent "vpgatherqq", 0, 2016
    mnc_ent "vplzcntd", 0, 2017
    mnc_ent "vplzcntq", 0, 2018
    mnc_ent "vpmadd52huq", 0, 2019
    mnc_ent "vpmadd52luq", 0, 2020
    mnc_ent "vpmaskmov", 0, 2021
    mnc_ent "vpmovb2m", 0, 2022
    mnc_ent "vpmovd2m", 0, 2023
    mnc_ent "vpmovdb", 0, 2024
    mnc_ent "vpmovdw", 0, 2025
    mnc_ent "vpmovm2b", 0, 2026
    mnc_ent "vpmovm2d", 0, 2027
    mnc_ent "vpmovm2q", 0, 2028
    mnc_ent "vpmovm2w", 0, 2029
    mnc_ent "vpmovq2m", 0, 2030
    mnc_ent "vpmovqb", 0, 2031
    mnc_ent "vpmovqd", 0, 2032
    mnc_ent "vpmovqw", 0, 2033
    mnc_ent "vpmovsdb", 0, 2034
    mnc_ent "vpmovsdw", 0, 2035
    mnc_ent "vpmovsqb", 0, 2036
    mnc_ent "vpmovsqd", 0, 2037
    mnc_ent "vpmovsqw", 0, 2038
    mnc_ent "vpmovswb", 0, 2039
    mnc_ent "vpmovusdb", 0, 2040
    mnc_ent "vpmovusdw", 0, 2041
    mnc_ent "vpmovusqb", 0, 2042
    mnc_ent "vpmovusqd", 0, 2043
    mnc_ent "vpmovusqw", 0, 2044
    mnc_ent "vpmovuswb", 0, 2045
    mnc_ent "vpmovw2m", 0, 2046
    mnc_ent "vpmovwb", 0, 2047
    mnc_ent "vpmultishiftqb", 0, 2048
    mnc_ent "vpopcnt", 0, 2049
    mnc_ent "vprold", 0, 2050
    mnc_ent "vprolq", 0, 2051
    mnc_ent "vprolvd", 0, 2052
    mnc_ent "vprolvq", 0, 2053
    mnc_ent "vprord", 0, 2054
    mnc_ent "vprorq", 0, 2055
    mnc_ent "vprorvd", 0, 2056
    mnc_ent "vprorvq", 0, 2057
    mnc_ent "vpscatterdd", 0, 2058
    mnc_ent "vpscatterdq", 0, 2059
    mnc_ent "vpscatterqd", 0, 2060
    mnc_ent "vpscatterqq", 0, 2061
    mnc_ent "vpshld", 0, 2062
    mnc_ent "vpshldv", 0, 2063
    mnc_ent "vpshrd", 0, 2064
    mnc_ent "vpshrdv", 0, 2065
    mnc_ent "vpshufbitqmb", 0, 2066
    mnc_ent "vpsllvd", 0, 2067
    mnc_ent "vpsllvq", 0, 2068
    mnc_ent "vpsllvw", 0, 2069
    mnc_ent "vpsravd", 0, 2070
    mnc_ent "vpsravq", 0, 2071
    mnc_ent "vpsravw", 0, 2072
    mnc_ent "vpsrlvd", 0, 2073
    mnc_ent "vpsrlvq", 0, 2074
    mnc_ent "vpsrlvw", 0, 2075
    mnc_ent "vpternlogd", 0, 2076
    mnc_ent "vpternlogq", 0, 2077
    mnc_ent "vptestmb", 0, 2078
    mnc_ent "vptestmd", 0, 2079
    mnc_ent "vptestmq", 0, 2080
    mnc_ent "vptestmw", 0, 2081
    mnc_ent "vptestnmb", 0, 2082
    mnc_ent "vptestnmd", 0, 2083
    mnc_ent "vptestnmq", 0, 2084
    mnc_ent "vptestnmw", 0, 2085
    mnc_ent "vrangepd", 0, 2086
    mnc_ent "vrangeps", 0, 2087
    mnc_ent "vrangesd", 0, 2088
    mnc_ent "vrangess", 0, 2089
    mnc_ent "vrcp14pd", 0, 2090
    mnc_ent "vrcp14ps", 0, 2091
    mnc_ent "vrcp14sd", 0, 2092
    mnc_ent "vrcp14ss", 0, 2093
    mnc_ent "vrcpph", 0, 2094
    mnc_ent "vrcpsh", 0, 2095
    mnc_ent "vreducepd", 0, 2096
    mnc_ent "vreduceph", 0, 2097
    mnc_ent "vreduceps", 0, 2098
    mnc_ent "vreducesd", 0, 2099
    mnc_ent "vreducesh", 0, 2100
    mnc_ent "vreducess", 0, 2101
    mnc_ent "vrndscalepd", 0, 2102
    mnc_ent "vrndscaleph", 0, 2103
    mnc_ent "vrndscaleps", 0, 2104
    mnc_ent "vrndscalesd", 0, 2105
    mnc_ent "vrndscalesh", 0, 2106
    mnc_ent "vrndscaless", 0, 2107
    mnc_ent "vrsqrt14pd", 0, 2108
    mnc_ent "vrsqrt14ps", 0, 2109
    mnc_ent "vrsqrt14sd", 0, 2110
    mnc_ent "vrsqrt14ss", 0, 2111
    mnc_ent "vrsqrtph", 0, 2112
    mnc_ent "vrsqrtsh", 0, 2113
    mnc_ent "vscalefpd", 0, 2114
    mnc_ent "vscalefph", 0, 2115
    mnc_ent "vscalefps", 0, 2116
    mnc_ent "vscalefsd", 0, 2117
    mnc_ent "vscalefsh", 0, 2118
    mnc_ent "vscalefss", 0, 2119
    mnc_ent "vscatterdpd", 0, 2120
    mnc_ent "vscatterdps", 0, 2121
    mnc_ent "vscatterqpd", 0, 2122
    mnc_ent "vscatterqps", 0, 2123
    mnc_ent "vshuff32x4", 0, 2124
    mnc_ent "vshuff64x2", 0, 2125
    mnc_ent "vshufi32x4", 0, 2126
    mnc_ent "vshufi64x2", 0, 2127
    mnc_ent "vsqrtph", 0, 2128
    mnc_ent "vsqrtsh", 0, 2129
    mnc_ent "vsubph", 0, 2130
    mnc_ent "vsubsh", 0, 2131
    mnc_ent "vtestpd", 0, 2132
    mnc_ent "vtestps", 0, 2133
    mnc_ent "vucomish", 0, 2134
    mnc_ent "vzeroall", 0, 2135
    mnc_ent "vzeroupper", 0, 2136
    mnc_ent "wait", 0, 2137
    mnc_ent "wbinvd", 0, 2138
    mnc_ent "wbnoinvd", 0, 2139
    mnc_ent "wrfsbase", 0, 2140
    mnc_ent "wrgsbase", 0, 2141
    mnc_ent "wrmsr", 0, 2142
    mnc_ent "wrpkru", 0, 2143
    mnc_ent "wrssd", 0, 2144
    mnc_ent "wrssq", 0, 2145
    mnc_ent "wrussd", 0, 2146
    mnc_ent "wrussq", 0, 2147
    mnc_ent "xabort", 0, 2148
    mnc_ent "xacquire", 0, 2149
    mnc_ent "xadd", 0, 2150
    mnc_ent "xbegin", 0, 2151
    mnc_ent "xchg", 0, 2152
    mnc_ent "xend", 0, 2153
    mnc_ent "xgetbv", 0, 2154
    mnc_ent "xlat", 0, 2155
    mnc_ent "xlatb", 0, 2156
    mnc_ent "xor", 0, 2157
    mnc_ent "xorpd", 0, 2158
    mnc_ent "xorps", 0, 2159
    mnc_ent "xrelease", 0, 2160
    mnc_ent "xresldtrk", 0, 2161
    mnc_ent "xrstor", 0, 2162
    mnc_ent "xrstors", 0, 2163
    mnc_ent "xsave", 0, 2164
    mnc_ent "xsavec", 0, 2165
    mnc_ent "xsaveopt", 0, 2166
    mnc_ent "xsaves", 0, 2167
    mnc_ent "xsetbv", 0, 2168
    mnc_ent "xsusldtrk", 0, 2169
    mnc_ent "xtest", 0, 2170
    
    ; ---- VMX / SVM Suite (Custom IDs) ----
    mnc_ent "vmcall", 0, 5000
    mnc_ent "vmlaunch", 0, 5001
    mnc_ent "vmresume", 0, 5002
    mnc_ent "vmxoff", 0, 5003
    mnc_ent "vmxon", 0, 5004
    mnc_ent "vmptrld", 0, 5005
    mnc_ent "vmptrst", 0, 5006
    mnc_ent "vmclear", 0, 5007
    mnc_ent "vmread", 0, 5008
    mnc_ent "vmwrite", 0, 5009
    mnc_ent "invept", 0, 5010
    mnc_ent "invvpid", 0, 5011
    
    ; AMD-V (SVM) Suite
    mnc_ent "vmrun", 0, 5012
    mnc_ent "vmmcall", 0, 5013
    mnc_ent "vmload", 0, 5014
    mnc_ent "vmsave", 0, 5015
    mnc_ent "clgi", 0, 5016
    mnc_ent "stgi", 0, 5017
    mnc_ent "invlpga", 0, 5018
    mnc_ent "skinit", 0, 5019
    mnc_ent "clzero", 0, 5020

    ; ---- Step 3 & 4: FMA3 & 8087 (Custom IDs) ----
    mnc_ent "fsin", 0, 5300
    mnc_ent "fcos", 0, 5301
    mnc_ent "fsincos", 0, 5302
    mnc_ent "fpatan", 0, 5303
    mnc_ent "fld1", 0, 5305
    mnc_ent "fldz", 0, 5306
    mnc_ent "fldpi", 0, 5307
    mnc_ent "fldln2", 0, 5308
    mnc_ent "fsave", 0, 5309
    mnc_ent "frstor", 0, 5310
    mnc_ent "fldenv", 0, 5311
    mnc_ent "fstenv", 0, 5312
    mnc_ent "flcw", 0, 5313
    mnc_ent "fstsw", 0, 5314
    mnc_ent "fucom", 0, 5315
    mnc_ent "fucompp", 0, 5316
    mnc_ent "fxtract", 0, 5317
    mnc_ent "fscale", 0, 5318
    
    ; ---- AVX-512 Suite (Custom IDs) ----
    mnc_ent "vaesenc", 0, 5100
    mnc_ent "vaesdec", 0, 5101
    mnc_ent "vaesenclast", 0, 5102
    mnc_ent "vaesdeclast", 0, 5103
    mnc_ent "vpclmulqdq", 0, 5104
    mnc_ent "vmovdqa64", 0, 5105
    mnc_ent "vaddpd", 0, 5106

    ; ---- Step 5: AVX-512 (Custom IDs) ----
    mnc_ent "kaddw", 0, 5400
    mnc_ent "kandw", 0, 5401
    mnc_ent "korw", 0, 5402
    mnc_ent "kxorw", 0, 5403
    mnc_ent "kmovw", 0, 5404
    mnc_ent "kunpckbw", 0, 5405
    mnc_ent "vgatherdpd", 0, 5406
    mnc_ent "vscatterdps", 0, 5407
    mnc_ent "vpconflictd", 0, 5408
    mnc_ent "vpconflictq", 0, 5409
    mnc_ent "vreducess", 0, 5410
    mnc_ent "vexp2ps", 0, 5411
    mnc_ent "vrcp14ps", 0, 5412

    ; ---- Step 6: VNNI & BF16 (Custom IDs) ----
    mnc_ent "vpdpbusd", 0, 5500
    mnc_ent "vpdpwssd", 0, 5501
    mnc_ent "vdpbf16ps", 0, 5502
    mnc_ent "vcvtne2ps2bf16", 0, 5503

    ; ---- Step 7: 3DNow! & XOP (Custom IDs) ----
    mnc_ent "femms", 0, 5600
    mnc_ent "pfadd", 0, 5601
    mnc_ent "pfcmpeq", 0, 5602
    mnc_ent "pfmax", 0, 5603
    mnc_ent "pfmin", 0, 5604
    mnc_ent "pfrcp", 0, 5605
    mnc_ent "pfrsqrt", 0, 5606
    mnc_ent "pi2fd", 0, 5607
    mnc_ent "vpmacssww", 0, 5608
    mnc_ent "vpmadcsswd", 0, 5609
    mnc_ent "vpperm", 0, 5610
    mnc_ent "vprotb", 0, 5611
    mnc_ent "vpshab", 0, 5612

    ; ---- Step 8: SGX Sub-Leafs (Custom IDs) ----
    mnc_ent "eadd", 0, 5700
    mnc_ent "eblock", 0, 5701
    mnc_ent "ecreate", 0, 5702
    mnc_ent "einit", 0, 5703
    mnc_ent "eenter", 0, 5704
    mnc_ent "eresume", 0, 5705
    mnc_ent "egetkey", 0, 5706

    dq 0

global amd64_register_table
amd64_register_table:
    ; ---- 64-bit GPRs ----
    compile_time_hash "rax", H_RAX
    dq H_RAX, (8 << 8) | REG_RAX
    compile_time_hash "rcx", H_RCX
    dq H_RCX, (8 << 8) | REG_RCX
    compile_time_hash "rdx", H_RDX
    dq H_RDX, (8 << 8) | REG_RDX
    compile_time_hash "rbx", H_RBX
    dq H_RBX, (8 << 8) | REG_RBX
    compile_time_hash "rsp", H_RSP
    dq H_RSP, (8 << 8) | REG_RSP
    compile_time_hash "rbp", H_RBP
    dq H_RBP, (8 << 8) | REG_RBP
    compile_time_hash "rsi", H_RSI
    dq H_RSI, (8 << 8) | REG_RSI
    compile_time_hash "rdi", H_RDI
    dq H_RDI, (8 << 8) | REG_RDI
    compile_time_hash "r8",  H_R8
    dq H_R8,  (8 << 8) | REG_R8
    compile_time_hash "r9",  H_R9
    dq H_R9,  (8 << 8) | REG_R9
    compile_time_hash "r10", H_R10
    dq H_R10, (8 << 8) | REG_R10
    compile_time_hash "r11", H_R11
    dq H_R11, (8 << 8) | REG_R11
    compile_time_hash "r12", H_R12
    dq H_R12, (8 << 8) | REG_R12
    compile_time_hash "r13", H_R13
    dq H_R13, (8 << 8) | REG_R13
    compile_time_hash "r14", H_R14
    dq H_R14, (8 << 8) | REG_R14
    compile_time_hash "r15", H_R15
    dq H_R15, (8 << 8) | REG_R15

    ; ---- 32-bit GPRs ----
    compile_time_hash "eax", H_EAX
    dq H_EAX, (4 << 8) | REG_RAX
    compile_time_hash "ecx", H_ECX
    dq H_ECX, (4 << 8) | REG_RCX
    compile_time_hash "edx", H_EDX
    dq H_EDX, (4 << 8) | REG_RDX
    compile_time_hash "ebx", H_EBX
    dq H_EBX, (4 << 8) | REG_RBX
    compile_time_hash "esi", H_ESI
    dq H_ESI, (4 << 8) | REG_RSI
    compile_time_hash "edi", H_EDI
    dq H_EDI, (4 << 8) | REG_RDI
    compile_time_hash "esp", H_ESP
    dq H_ESP, (4 << 8) | REG_RSP
    compile_time_hash "ebp", H_EBP
    dq H_EBP, (4 << 8) | REG_RBP
    compile_time_hash "r8d", H_R8D
    dq H_R8D, (4 << 8) | 8
    compile_time_hash "r9d", H_R9D
    dq H_R9D, (4 << 8) | 9
    compile_time_hash "r10d", H_R10D
    dq H_R10D, (4 << 8) | 10
    compile_time_hash "r11d", H_R11D
    dq H_R11D, (4 << 8) | 11
    compile_time_hash "r12d", H_R12D
    dq H_R12D, (4 << 8) | 12
    compile_time_hash "r13d", H_R13D
    dq H_R13D, (4 << 8) | 13
    compile_time_hash "r14d", H_R14D
    dq H_R14D, (4 << 8) | 14
    compile_time_hash "r15d", H_R15D
    dq H_R15D, (4 << 8) | 15

    ; ---- 16-bit GPRs ----
    compile_time_hash "ax", H_AX
    dq H_AX, (2 << 8) | REG_RAX
    compile_time_hash "cx", H_CX
    dq H_CX, (2 << 8) | REG_RCX
    compile_time_hash "dx", H_DX
    dq H_DX, (2 << 8) | REG_RDX
    compile_time_hash "bx", H_BX
    dq H_BX, (2 << 8) | REG_RBX
    compile_time_hash "si", H_SI
    dq H_SI, (2 << 8) | REG_RSI
    compile_time_hash "di", H_DI
    dq H_DI, (2 << 8) | REG_RDI
    compile_time_hash "sp", H_SP
    dq H_SP, (2 << 8) | REG_RSP
    compile_time_hash "bp", H_BP
    dq H_BP, (2 << 8) | REG_RBP
    compile_time_hash "r8w", H_R8W
    dq H_R8W, (2 << 8) | 8
    compile_time_hash "r9w", H_R9W
    dq H_R9W, (2 << 8) | 9
    compile_time_hash "r10w", H_R10W
    dq H_R10W, (2 << 8) | 10
    compile_time_hash "r11w", H_R11W
    dq H_R11W, (2 << 8) | 11
    compile_time_hash "r12w", H_R12W
    dq H_R12W, (2 << 8) | 12
    compile_time_hash "r13w", H_R13W
    dq H_R13W, (2 << 8) | 13
    compile_time_hash "r14w", H_R14W
    dq H_R14W, (2 << 8) | 14
    compile_time_hash "r15w", H_R15W
    dq H_R15W, (2 << 8) | 15

    ; ---- 8-bit GPRs (Low) ----
    compile_time_hash "al", H_AL
    dq H_AL, (1 << 8) | REG_RAX
    compile_time_hash "cl", H_CL
    dq H_CL, (1 << 8) | REG_RCX
    compile_time_hash "dl", H_DL
    dq H_DL, (1 << 8) | REG_RDX
    compile_time_hash "bl", H_BL
    dq H_BL, (1 << 8) | REG_RBX
    compile_time_hash "sil", H_SIL
    dq H_SIL, (1 << 8) | REG_RSI
    compile_time_hash "dil", H_DIL
    dq H_DIL, (1 << 8) | REG_RDI
    compile_time_hash "spl", H_SPL
    dq H_SPL, (1 << 8) | REG_RSP
    compile_time_hash "bpl", H_BPL
    dq H_BPL, (1 << 8) | REG_RBP
    compile_time_hash "r8b", H_R8B
    dq H_R8B, (1 << 8) | 8
    compile_time_hash "r9b", H_R9B
    dq H_R9B, (1 << 8) | 9
    compile_time_hash "r10b", H_R10B
    dq H_R10B, (1 << 8) | 10
    compile_time_hash "r11b", H_R11B
    dq H_R11B, (1 << 8) | 11
    compile_time_hash "r12b", H_R12B
    dq H_R12B, (1 << 8) | 12
    compile_time_hash "r13b", H_R13B
    dq H_R13B, (1 << 8) | 13
    compile_time_hash "r14b", H_R14B
    dq H_R14B, (1 << 8) | 14
    compile_time_hash "r15b", H_R15B
    dq H_R15B, (1 << 8) | 15

    ; ---- 8-bit GPRs (High) ----
    compile_time_hash "ah", H_AH
    dq H_AH, (1 << 16) | (1 << 8) | 4
    compile_time_hash "ch", H_CH
    dq H_CH, (1 << 16) | (1 << 8) | 5
    compile_time_hash "dh", H_DH
    dq H_DH, (1 << 16) | (1 << 8) | 6
    compile_time_hash "bh", H_BH
    dq H_BH, (1 << 16) | (1 << 8) | 7

    ; ---- SIMD (XMM) ----
    %assign i 0
    ; ---- SIMD (XMM/YMM/ZMM) ----
    compile_time_hash "xmm0", H_XMM0
    dq H_XMM0, (16 << 8) | 80
    compile_time_hash "xmm1", H_XMM1
    dq H_XMM1, (16 << 8) | 81
    compile_time_hash "xmm2", H_XMM2
    dq H_XMM2, (16 << 8) | 82
    compile_time_hash "xmm3", H_XMM3
    dq H_XMM3, (16 << 8) | 83
    compile_time_hash "xmm4", H_XMM4
    dq H_XMM4, (16 << 8) | 84
    compile_time_hash "xmm5", H_XMM5
    dq H_XMM5, (16 << 8) | 85
    compile_time_hash "xmm6", H_XMM6
    dq H_XMM6, (16 << 8) | 86
    compile_time_hash "xmm7", H_XMM7
    dq H_XMM7, (16 << 8) | 87
    compile_time_hash "xmm8", H_XMM8
    dq H_XMM8, (16 << 8) | 88
    compile_time_hash "xmm9", H_XMM9
    dq H_XMM9, (16 << 8) | 89
    compile_time_hash "xmm10", H_XMM10
    dq H_XMM10, (16 << 8) | 90
    compile_time_hash "xmm11", H_XMM11
    dq H_XMM11, (16 << 8) | 91
    compile_time_hash "xmm12", H_XMM12
    dq H_XMM12, (16 << 8) | 92
    compile_time_hash "xmm13", H_XMM13
    dq H_XMM13, (16 << 8) | 93
    compile_time_hash "xmm14", H_XMM14
    dq H_XMM14, (16 << 8) | 94
    compile_time_hash "xmm15", H_XMM15
    dq H_XMM15, (16 << 8) | 95
    compile_time_hash "xmm16", H_XMM16
    dq H_XMM16, (16 << 8) | 96
    compile_time_hash "xmm17", H_XMM17
    dq H_XMM17, (16 << 8) | 97
    compile_time_hash "xmm18", H_XMM18
    dq H_XMM18, (16 << 8) | 98
    compile_time_hash "xmm19", H_XMM19
    dq H_XMM19, (16 << 8) | 99
    compile_time_hash "xmm20", H_XMM20
    dq H_XMM20, (16 << 8) | 100
    compile_time_hash "xmm21", H_XMM21
    dq H_XMM21, (16 << 8) | 101
    compile_time_hash "xmm22", H_XMM22
    dq H_XMM22, (16 << 8) | 102
    compile_time_hash "xmm23", H_XMM23
    dq H_XMM23, (16 << 8) | 103
    compile_time_hash "xmm24", H_XMM24
    dq H_XMM24, (16 << 8) | 104
    compile_time_hash "xmm25", H_XMM25
    dq H_XMM25, (16 << 8) | 105
    compile_time_hash "xmm26", H_XMM26
    dq H_XMM26, (16 << 8) | 106
    compile_time_hash "xmm27", H_XMM27
    dq H_XMM27, (16 << 8) | 107
    compile_time_hash "xmm28", H_XMM28
    dq H_XMM28, (16 << 8) | 108
    compile_time_hash "xmm29", H_XMM29
    dq H_XMM29, (16 << 8) | 109
    compile_time_hash "xmm30", H_XMM30
    dq H_XMM30, (16 << 8) | 110
    compile_time_hash "xmm31", H_XMM31
    dq H_XMM31, (16 << 8) | 111
    compile_time_hash "ymm0", H_YMM0
    dq H_YMM0, (32 << 8) | 80
    compile_time_hash "ymm1", H_YMM1
    dq H_YMM1, (32 << 8) | 81
    compile_time_hash "ymm2", H_YMM2
    dq H_YMM2, (32 << 8) | 82
    compile_time_hash "ymm3", H_YMM3
    dq H_YMM3, (32 << 8) | 83
    compile_time_hash "ymm4", H_YMM4
    dq H_YMM4, (32 << 8) | 84
    compile_time_hash "ymm5", H_YMM5
    dq H_YMM5, (32 << 8) | 85
    compile_time_hash "ymm6", H_YMM6
    dq H_YMM6, (32 << 8) | 86
    compile_time_hash "ymm7", H_YMM7
    dq H_YMM7, (32 << 8) | 87
    compile_time_hash "ymm8", H_YMM8
    dq H_YMM8, (32 << 8) | 88
    compile_time_hash "ymm9", H_YMM9
    dq H_YMM9, (32 << 8) | 89
    compile_time_hash "ymm10", H_YMM10
    dq H_YMM10, (32 << 8) | 90
    compile_time_hash "ymm11", H_YMM11
    dq H_YMM11, (32 << 8) | 91
    compile_time_hash "ymm12", H_YMM12
    dq H_YMM12, (32 << 8) | 92
    compile_time_hash "ymm13", H_YMM13
    dq H_YMM13, (32 << 8) | 93
    compile_time_hash "ymm14", H_YMM14
    dq H_YMM14, (32 << 8) | 94
    compile_time_hash "ymm15", H_YMM15
    dq H_YMM15, (32 << 8) | 95
    compile_time_hash "ymm16", H_YMM16
    dq H_YMM16, (32 << 8) | 96
    compile_time_hash "ymm17", H_YMM17
    dq H_YMM17, (32 << 8) | 97
    compile_time_hash "ymm18", H_YMM18
    dq H_YMM18, (32 << 8) | 98
    compile_time_hash "ymm19", H_YMM19
    dq H_YMM19, (32 << 8) | 99
    compile_time_hash "ymm20", H_YMM20
    dq H_YMM20, (32 << 8) | 100
    compile_time_hash "ymm21", H_YMM21
    dq H_YMM21, (32 << 8) | 101
    compile_time_hash "ymm22", H_YMM22
    dq H_YMM22, (32 << 8) | 102
    compile_time_hash "ymm23", H_YMM23
    dq H_YMM23, (32 << 8) | 103
    compile_time_hash "ymm24", H_YMM24
    dq H_YMM24, (32 << 8) | 104
    compile_time_hash "ymm25", H_YMM25
    dq H_YMM25, (32 << 8) | 105
    compile_time_hash "ymm26", H_YMM26
    dq H_YMM26, (32 << 8) | 106
    compile_time_hash "ymm27", H_YMM27
    dq H_YMM27, (32 << 8) | 107
    compile_time_hash "ymm28", H_YMM28
    dq H_YMM28, (32 << 8) | 108
    compile_time_hash "ymm29", H_YMM29
    dq H_YMM29, (32 << 8) | 109
    compile_time_hash "ymm30", H_YMM30
    dq H_YMM30, (32 << 8) | 110
    compile_time_hash "ymm31", H_YMM31
    dq H_YMM31, (32 << 8) | 111
    compile_time_hash "zmm0", H_ZMM0
    dq H_ZMM0, (64 << 8) | 80
    compile_time_hash "zmm1", H_ZMM1
    dq H_ZMM1, (64 << 8) | 81
    compile_time_hash "zmm2", H_ZMM2
    dq H_ZMM2, (64 << 8) | 82
    compile_time_hash "zmm3", H_ZMM3
    dq H_ZMM3, (64 << 8) | 83
    compile_time_hash "zmm4", H_ZMM4
    dq H_ZMM4, (64 << 8) | 84
    compile_time_hash "zmm5", H_ZMM5
    dq H_ZMM5, (64 << 8) | 85
    compile_time_hash "zmm6", H_ZMM6
    dq H_ZMM6, (64 << 8) | 86
    compile_time_hash "zmm7", H_ZMM7
    dq H_ZMM7, (64 << 8) | 87
    compile_time_hash "zmm8", H_ZMM8
    dq H_ZMM8, (64 << 8) | 88
    compile_time_hash "zmm9", H_ZMM9
    dq H_ZMM9, (64 << 8) | 89
    compile_time_hash "zmm10", H_ZMM10
    dq H_ZMM10, (64 << 8) | 90
    compile_time_hash "zmm11", H_ZMM11
    dq H_ZMM11, (64 << 8) | 91
    compile_time_hash "zmm12", H_ZMM12
    dq H_ZMM12, (64 << 8) | 92
    compile_time_hash "zmm13", H_ZMM13
    dq H_ZMM13, (64 << 8) | 93
    compile_time_hash "zmm14", H_ZMM14
    dq H_ZMM14, (64 << 8) | 94
    compile_time_hash "zmm15", H_ZMM15
    dq H_ZMM15, (64 << 8) | 95
    compile_time_hash "zmm16", H_ZMM16
    dq H_ZMM16, (64 << 8) | 96
    compile_time_hash "zmm17", H_ZMM17
    dq H_ZMM17, (64 << 8) | 97
    compile_time_hash "zmm18", H_ZMM18
    dq H_ZMM18, (64 << 8) | 98
    compile_time_hash "zmm19", H_ZMM19
    dq H_ZMM19, (64 << 8) | 99
    compile_time_hash "zmm20", H_ZMM20
    dq H_ZMM20, (64 << 8) | 100
    compile_time_hash "zmm21", H_ZMM21
    dq H_ZMM21, (64 << 8) | 101
    compile_time_hash "zmm22", H_ZMM22
    dq H_ZMM22, (64 << 8) | 102
    compile_time_hash "zmm23", H_ZMM23
    dq H_ZMM23, (64 << 8) | 103
    compile_time_hash "zmm24", H_ZMM24
    dq H_ZMM24, (64 << 8) | 104
    compile_time_hash "zmm25", H_ZMM25
    dq H_ZMM25, (64 << 8) | 105
    compile_time_hash "zmm26", H_ZMM26
    dq H_ZMM26, (64 << 8) | 106
    compile_time_hash "zmm27", H_ZMM27
    dq H_ZMM27, (64 << 8) | 107
    compile_time_hash "zmm28", H_ZMM28
    dq H_ZMM28, (64 << 8) | 108
    compile_time_hash "zmm29", H_ZMM29
    dq H_ZMM29, (64 << 8) | 109
    compile_time_hash "zmm30", H_ZMM30
    dq H_ZMM30, (64 << 8) | 110
    compile_time_hash "zmm31", H_ZMM31
    dq H_ZMM31, (64 << 8) | 111

    ; ---- Opmask (K0-K7) ----
    compile_time_hash "k0", H_K0
    dq H_K0, (8 << 8) | 72
    compile_time_hash "k1", H_K1
    dq H_K1, (8 << 8) | 73
    compile_time_hash "k2", H_K2
    dq H_K2, (8 << 8) | 74
    compile_time_hash "k3", H_K3
    dq H_K3, (8 << 8) | 75
    compile_time_hash "k4", H_K4
    dq H_K4, (8 << 8) | 76
    compile_time_hash "k5", H_K5
    dq H_K5, (8 << 8) | 77
    compile_time_hash "k6", H_K6
    dq H_K6, (8 << 8) | 78
    compile_time_hash "k7", H_K7
    dq H_K7, (8 << 8) | 79

    ; ---- Control Registers (CR0-CR15) ----
    compile_time_hash "cr0", H_CR0
    dq H_CR0, (8 << 8) | 32
    compile_time_hash "cr1", H_CR1
    dq H_CR1, (8 << 8) | 33
    compile_time_hash "cr2", H_CR2
    dq H_CR2, (8 << 8) | 34
    compile_time_hash "cr3", H_CR3
    dq H_CR3, (8 << 8) | 35
    compile_time_hash "cr4", H_CR4
    dq H_CR4, (8 << 8) | 36
    compile_time_hash "cr5", H_CR5
    dq H_CR5, (8 << 8) | 37
    compile_time_hash "cr6", H_CR6
    dq H_CR6, (8 << 8) | 38
    compile_time_hash "cr7", H_CR7
    dq H_CR7, (8 << 8) | 39
    compile_time_hash "cr8", H_CR8
    dq H_CR8, (8 << 8) | 40
    compile_time_hash "cr9", H_CR9
    dq H_CR9, (8 << 8) | 41
    compile_time_hash "cr10", H_CR10
    dq H_CR10, (8 << 8) | 42
    compile_time_hash "cr11", H_CR11
    dq H_CR11, (8 << 8) | 43
    compile_time_hash "cr12", H_CR12
    dq H_CR12, (8 << 8) | 44
    compile_time_hash "cr13", H_CR13
    dq H_CR13, (8 << 8) | 45
    compile_time_hash "cr14", H_CR14
    dq H_CR14, (8 << 8) | 46
    compile_time_hash "cr15", H_CR15
    dq H_CR15, (8 << 8) | 47

    ; ---- Debug Registers (DR0-DR15) ----
    compile_time_hash "dr0", H_DR0
    dq H_DR0, (8 << 8) | 48
    compile_time_hash "dr1", H_DR1
    dq H_DR1, (8 << 8) | 49
    compile_time_hash "dr2", H_DR2
    dq H_DR2, (8 << 8) | 50
    compile_time_hash "dr3", H_DR3
    dq H_DR3, (8 << 8) | 51
    compile_time_hash "dr4", H_DR4
    dq H_DR4, (8 << 8) | 52
    compile_time_hash "dr5", H_DR5
    dq H_DR5, (8 << 8) | 53
    compile_time_hash "dr6", H_DR6
    dq H_DR6, (8 << 8) | 54
    compile_time_hash "dr7", H_DR7
    dq H_DR7, (8 << 8) | 55
    compile_time_hash "dr8", H_DR8
    dq H_DR8, (8 << 8) | 56
    compile_time_hash "dr9", H_DR9
    dq H_DR9, (8 << 8) | 57
    compile_time_hash "dr10", H_DR10
    dq H_DR10, (8 << 8) | 58
    compile_time_hash "dr11", H_DR11
    dq H_DR11, (8 << 8) | 59
    compile_time_hash "dr12", H_DR12
    dq H_DR12, (8 << 8) | 60
    compile_time_hash "dr13", H_DR13
    dq H_DR13, (8 << 8) | 61
    compile_time_hash "dr14", H_DR14
    dq H_DR14, (8 << 8) | 62
    compile_time_hash "dr15", H_DR15
    dq H_DR15, (8 << 8) | 63

    ; ---- Segments ----
    compile_time_hash "cs", H_CS
    dq H_CS, (2 << 8) | REG_CS
    compile_time_hash "ds", H_DS
    dq H_DS, (2 << 8) | REG_DS
    compile_time_hash "fs", H_FS
    dq H_FS, (2 << 8) | REG_FS
    compile_time_hash "gs", H_GS
    dq H_GS, (2 << 8) | REG_GS
    compile_time_hash "ss", H_SS
    dq H_SS, (2 << 8) | REG_SS

    dq 0
