load("@io_bazel_rules_go//go:def.bzl", "go_binary")

go_binary(
    name = "go_sfu",
    srcs = glob(["*.go"]),
    cgo = True,
    linkmode = "c-archive",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pion_datachannel//:datachannel",
        "@com_github_pion_dtls_v3//:dtls",
        "@com_github_pion_ice_v4//:ice",
        "@com_github_pion_logging//:logging",
        "@com_github_pion_rtcp//:rtcp",
        "@com_github_pion_sctp//:sctp",
        "@com_github_pion_srtp_v3//:srtp",
    ],
)
