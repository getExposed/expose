package server

import (
	"errors"
	"fmt"
	"net"
	"net/http"

	"go.uber.org/zap"
)

type HTTPServer struct {
	*http.Server
	listener  net.Listener
	isRunning bool
	running   chan error
	logger    *zap.SugaredLogger
}

func NewHTTPServer(logger *zap.SugaredLogger) *HTTPServer {
	return &HTTPServer{
		Server:    &http.Server{},
		running:   make(chan error, 1),
		logger:    logger,
		isRunning: false,
	}
}

func (h *HTTPServer) Run(addr string, handler http.Handler) error {
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	h.Handler = handler
	h.listener = listener
	h.isRunning = true

	h.logger.Infof("starting HTTP server on %s", addr)

	go h.closeWith(h.Serve(listener))
	return nil
}

func (h *HTTPServer) Close() error {
	h.closeWith(nil)
	if h.listener != nil {
		return h.listener.Close()
	}
	return nil
}

func (h *HTTPServer) Wait() error {
	if !h.isRunning {
		return fmt.Errorf("already closed")
	}
	return <-h.running
}

func (h *HTTPServer) closeWith(err error) {
	if !h.isRunning {
		return
	}
	h.isRunning = false

	if errors.Is(err, http.ErrServerClosed) {
		err = nil
	}

	// Non-blocking send so we don't deadlock if nobody is waiting yet/already received.
	select {
	case h.running <- err:
	default:
	}
}
