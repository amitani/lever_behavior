import serial, argparse, sys

parser=argparse.ArgumentParser(description='Dump serial port input to a file.');
parser.add_argument('outfile',nargs='?',default=None);
parser.add_argument('--serial','-s',default='/dev/tty.usbserial');
parser.add_argument('--baudrate','-b',type=int,default=230400);
parser.add_argument('--max_size','-m',type=int,default=100*1024*1024);
args=parser.parse_args()

if args.outfile:
    of=open(args.outfile,'wb')
else:
    of=None
try:
    ser = serial.Serial(args.serial, args.baudrate, timeout=10)
    bytes_to_write=args.max_size
    while bytes_to_write>0:
        b=ser.read()
        if of:
            of.write(b)
        else:
            print(b.encode("hex")),
        bytes_to_write-=len(b)
finally:
    print '\nClosing serial ports and files...\n'
    try:
        ser.close()
    except:
        pass
    try:
        of.close()
    except:
        pass
    sys.exit(0)
