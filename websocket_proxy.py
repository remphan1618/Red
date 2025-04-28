#!/usr/bin/env python3
import argparse
import logging
import sys
import websockify.websocketproxy

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('websocket_proxy')

def main():
    parser = argparse.ArgumentParser(description='WebSockets proxy for VNC')
    parser.add_argument('--listen', required=True, 
                       help='Listen address and port (e.g., 0.0.0.0:6080)')
    parser.add_argument('--target', required=True,
                       help='Target VNC server address and port (e.g., localhost:5901)')
    
    try:
        args = parser.parse_args()
        
        # Properly parse the listen address and port
        if ':' not in args.listen:
            raise ValueError(f"Invalid listen format: {args.listen}. Expected format: address:port")
        
        listen_parts = args.listen.rsplit(':', 1)
        listen_host = listen_parts[0] or '0.0.0.0'  # Default to all interfaces if empty
        
        # Ensure port is a valid integer
        try:
            listen_port = int(listen_parts[1])
            if listen_port < 1 or listen_port > 65535:
                raise ValueError(f"Port number out of range: {listen_port}")
        except ValueError:
            raise ValueError(f"Invalid port number: {listen_parts[1]}")
        
        logger.info(f"Starting WebSockets proxy on {listen_host}:{listen_port}")
        
        server = websockify.websocketproxy.WebSocketProxy(
            listen_host=listen_host,
            listen_port=listen_port,
            target_host=args.target.split(':')[0],
            target_port=int(args.target.split(':')[1]),
            verbose=True
        )
        server.start_server()
        
    except ValueError as e:
        logger.error(f"Error parsing arguments: {e}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to start WebSockets proxy: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
