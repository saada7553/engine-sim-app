#ifndef ATG_ENGINE_SIM_OSCILLOSCOPE_H
#define ATG_ENGINE_SIM_OSCILLOSCOPE_H

class Oscilloscope {
    public:
        struct DataPoint {
            double x, y;
        };

    public:
        Oscilloscope();
        virtual ~Oscilloscope();
        virtual void destroy();

        void addDataPoint(double x, double y);
        void setBufferSize(int n);
        void reset();

        double m_xMin;
        double m_xMax;

        double m_yMin;
        double m_yMax;

        double m_dynamicallyResizeX;
        double m_dynamicallyResizeY;

        double m_lineWidth;
        bool m_drawReverse;
        bool m_drawZero;
        
        DataPoint *getDataPoints() const { return m_points; }
        int getWriteIndex() const { return m_writeIndex; }
        int getBufferSize() const { return m_bufferSize; }
        int getPointCount() const { return m_pointCount; }

    protected:
        DataPoint *m_points;
        int m_writeIndex;
        int m_bufferSize;
        int m_pointCount;
};

#endif /* ATG_ENGINE_SIM_OSCILLOSCOPE_H */
