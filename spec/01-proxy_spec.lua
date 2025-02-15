local cjson = require "cjson"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do

  describe("gRPC-Gateway [#" .. strategy .. "]", function()
    local proxy_client


    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "grpc-gateway",
      })

      -- the sample server we used is from
      -- https://github.com/grpc/grpc-go/tree/master/examples/features/reflection
      -- which listens 50051 by default
      local service1 = assert(bp.services:insert {
        name = "grpc",
        protocol = "grpc",
        host = "localhost",
        port = 15002,
      })

      local route1 = assert(bp.routes:insert {
        protocols = { "http", "https" },
        paths = { "/" },
        service = service1,
      })

      assert(bp.plugins:insert {
        route = route1,
        name = "grpc-gateway",
        config = {
          proto = "spec/fixtures/grpc/helloworld.proto",
        },
      })

      assert(helpers.start_kong {
        database = strategy,
        plugins = "bundled,grpc-gateway",
      })
    end)

    before_each(function()
      proxy_client = helpers.proxy_client(1000)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    test("main entrypoint", function()
      local res, err = proxy_client:get("/v1/messages/john_doe")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local body = res:read_body()
      local data = cjson.decode(body)

      assert.same({reply = "hello john_doe"}, data)
    end)

    test("additional binding", function()
      local res, err = proxy_client:get("/v1/messages/legacy/john_doe")

      assert.equal(200, res.status)
      assert.is_nil(err)

      local data = cjson.decode((res:read_body()))

      assert.same({reply = "hello john_doe"}, data)
    end)

    test("unknown path", function()
      local res, _ = proxy_client:get("/v1/messages/john_doe/bai")
      assert.not_equal(200, res.status)
      assert.equal("Bad Request", res.reason)
    end)

  end)
end
