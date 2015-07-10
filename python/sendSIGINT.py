import argparse,sys,os,signal
parser=argparse.ArgumentParser('Send SIGINT to PID.')
parser.add_argument('pid',type=int)
args=parser.parse_args()
os.kill(args.pid,signal.SIGINT)
